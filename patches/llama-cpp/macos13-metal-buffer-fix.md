# llama.cpp Metal fix for macOS ≤ 13.x — `GGML_ASSERT(buf_dst)` crash

## Symptom

On older macOS (verified on 13.3 / Apple Silicon), `llama-server` / `llama-cli` aborts while
loading or running Qwen3.5-hybrid models (including CogEvol-4B):

```
Assertion failed: buf_dst, file ggml/src/ggml-metal/ggml-metal-context.m, line ~361
```

## Root cause

`ggml_metal_get_tensor_async` wraps the destination host pointer with
`newBufferWithBytesNoCopy`. On macOS ≤ 13 the Metal driver returns `nil` for that call
unless **both** the pointer and the size are page-aligned — including for the zero-length
copy llama.cpp issues during warmup. The assert then kills the process. Newer macOS
versions tolerate these wraps, which is why upstream CI does not catch it.

We observed it with llama.cpp `0.3.0-dev` builds from August 2026; it may be fixed
upstream by the time you read this — try running without this fix first, and apply it
only if you hit the assert.

## Fix

Replace the body of `ggml_metal_get_tensor_async` in
`ggml/src/ggml-metal/ggml-metal-context.m` with the version below (two changes: an early
return for `size == 0`, and a page-alignment check with a synchronous staging-buffer
fallback):

```objc
void ggml_metal_get_tensor_async(ggml_metal_t ctx, const struct ggml_tensor * tensor, void * data, size_t offset, size_t size) {
    @autoreleasepool {
        if (size == 0) {
            return;
        }

        // newBufferWithBytesNoCopy requires a page-aligned pointer and a page-aligned size
        const size_t page_size = (size_t) sysconf(_SC_PAGESIZE);
        const bool can_wrap = ((uintptr_t)data % page_size == 0) && (size % page_size == 0);

        id<MTLDevice> device = ggml_metal_device_get_obj(ctx->dev);

        id<MTLBuffer> buf_dst = nil;
        void * staging_data = NULL;

        if (can_wrap) {
            buf_dst = [device newBufferWithBytesNoCopy:data
                                                length:size
                                                options:MTLResourceStorageModeShared
                                            deallocator:nil];

            GGML_ASSERT(buf_dst);
        }

        struct ggml_metal_buffer_id bid_src = ggml_metal_get_buffer_id(tensor);
        if (bid_src.metal == nil) {
            if (buf_dst) {
                [buf_dst release];
            }
            GGML_ABORT("%s: failed to find buffer for tensor '%s'\n", __func__, tensor->name);
        }

        bid_src.offs += offset;

        // queue the copy operation into the queue of the Metal context
        // this will be queued at the end, after any currently ongoing GPU operations
        id<MTLCommandQueue> queue = ggml_metal_device_get_queue(ctx->dev);
        id<MTLCommandBuffer> cmd_buf = [queue commandBuffer];
        id<MTLBlitCommandEncoder> encoder = [cmd_buf blitCommandEncoder];

        if (buf_dst) {
            [encoder copyFromBuffer:bid_src.metal
                       sourceOffset:bid_src.offs
                           toBuffer:buf_dst
                  destinationOffset:0
                               size:size];

            [encoder endEncoding];
            [cmd_buf commit];
            [buf_dst release];

            // do not wait here for completion
            //[cmd_buf waitUntilCompleted];

            // instead, remember a reference to the command buffer and wait for it later if needed
            [ctx->cmd_bufs_ext addObject:cmd_buf];
            ctx->cmd_buf_last = cmd_buf;

            [cmd_buf retain];

            return;
        }

        // the host buffer cannot be wrapped directly (not page-aligned) - fall back to a
        // synchronous copy through an aligned staging buffer to avoid failing on older macOS
        GGML_LOG_WARN("%s: host buffer is not page-wrappable (ptr = %p, size = %zu), using synchronous copy\n", __func__, data, size);

        const size_t staging_size = (size + page_size - 1) & ~(page_size - 1);

        if (posix_memalign(&staging_data, page_size, staging_size) != 0) {
            GGML_ABORT("%s: failed to allocate staging buffer\n", __func__);
        }

        id<MTLBuffer> buf_staging = [device newBufferWithBytesNoCopy:staging_data
                                                              length:staging_size
                                                              options:MTLResourceStorageModeShared
                                                          deallocator:nil];

        if (buf_staging == nil) {
            free(staging_data);
            GGML_ABORT("%s: failed to create staging buffer\n", __func__);
        }

        [encoder copyFromBuffer:bid_src.metal
                   sourceOffset:bid_src.offs
                       toBuffer:buf_staging
              destinationOffset:0
                           size:size];

        [encoder endEncoding];
        [cmd_buf commit];
        [cmd_buf waitUntilCompleted];

        memcpy(data, buf_staging.contents, size);

        [buf_staging release];
        free(staging_data);
    }
}
```

Then rebuild llama.cpp. The warning line
`host buffer is not page-wrappable ... using synchronous copy` appearing a handful of
times in the log is expected and harmless (it fires once per unaligned tensor fetch —
measured cost is negligible relative to generation time).

## Related pitfall: prebuilt binaries refuse to load

Official prebuilt macOS arm64 binaries from the same period are built against a newer
macOS SDK (`minos 26`); on macOS 13 `dyld` rejects them outright
(`Symbol not found: _MTLResidencySetDescriptor`). Building from source with the local SDK
(as README §2 does) avoids both this and the assert above.
