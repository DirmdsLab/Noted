# 1. Executive Summary

**Analyzed repository:** `boykopovar/AnyPS5`  
**Analyzed commit:** `3c054008b8211405583e60c47eb13ca026e8eb10`

**FACT:** AnyPS5 is not a conventional emulator. The README explicitly states that it performs automatic executable porting and has “no emulation or separate runtime process.”

The actual execution model is:

1. A PS5 ELF is parsed and validated.
2. PS5-specific dynamic tags, NID imports, relocations, and module metadata are translated into a SysV/Linux ELF or Windows PE-compatible layout.
3. The original x86-64 machine code remains native machine code.
4. Imported PS5 functions are resolved by dynamically linked `.prx` libraries implemented by AnyPS5.
5. PS5 AGC command buffers are interpreted by the host-side `libSceAgcDriver`.
6. RDNA shader binaries are decoded, translated through an IR, emitted as SPIR-V, and executed by Vulkan.
7. Memory, threads, input, audio, video output, filesystem, and system services are mapped to host APIs.

The most important architectural conclusion is:

> The game CPU code executes directly on the host x86-64 CPU. Only PS5 platform dependencies and GPU shader/command semantics are translated.

The system is therefore best understood as a **binary relinker plus native PS5 API compatibility layer plus GPU command/shader translation stack**, rather than an instruction-by-instruction CPU emulator.

---

# 2. Repository Map

## Top-level tree

```text
AnyPS5/
├── CMakeLists.txt
├── core/
│   ├── Decoder/
│   │   ├── Jpeg/
│   │   └── Png/
│   ├── libs/
│   │   ├── nid/
│   │   ├── prx/
│   │   │   ├── libc/
│   │   │   ├── libkernel/
│   │   │   ├── libSceAgc/
│   │   │   ├── libSceAgcDriver/
│   │   │   ├── libSceVideoOut/
│   │   │   ├── libScePad/
│   │   │   ├── libSceAudioOut/
│   │   │   ├── libSceAudiodec/
│   │   │   ├── libSceAvPlayer/
│   │   │   └── many additional PRX libraries
│   │   └── tests/
│   ├── relinker/
│   │   ├── cli/
│   │   ├── codegen/
│   │   ├── domain/
│   │   ├── elfpatcher/
│   │   ├── io/
│   │   └── relinker/
│   └── shader/
│       └── recompiler/
├── 3rdparty/
│   ├── SDL2/
│   ├── Vulkan-Headers/
│   ├── SPIRV-Headers/
│   ├── SPIRV-Tools/
│   ├── glslang/
│   ├── VulkanMemoryAllocator/
│   ├── ffmpeg-core/
│   ├── freetype/
│   ├── libjpeg-turbo/
│   └── LibAtrac9/
├── docs/
│   ├── dev/
│   └── user/
└── tools/
```

## Subsystem table

| Path | Subsystem | Responsibility | Important Files | Runtime Critical? | Performance Critical? |
|---|---|---|---|---:|---:|
| `core/relinker` | Executable conversion | Converts PS5 ELF to Linux ELF/Windows PE | `main.cpp`, `RelinkerPipeline.cpp`, `LinuxElfPatcher.cpp`, `GuestModuleBuilder.cpp` | Yes, startup | Medium |
| `core/relinker/codegen` | x86-64 rewriting | Handles AMD-only instructions for Intel hosts | `Amd64OnlyConverter.cpp`, `x86/*` | Optional | Medium |
| `core/relinker/elfpatcher` | ELF/PE output | Rebuilds program headers, dynamic sections, entry stubs, Windows loader structures | `LinuxElfPatcher.cpp`, `WindowsPePatcher.cpp`, `EntryStubBuilder.cpp` | Yes, startup | Low |
| `core/relinker/io` | Binary I/O | Bounds-checked byte parsing and writing | `ByteReader.cpp`, `ByteWriter.cpp`, `FileReader.cpp` | Yes | Low |
| `core/libs/nid` | NID patching | Renames/patches exported/imported symbols and dynamic hash data | `ElfNidPatcher.cpp`, `PeNidPatcher.cpp` | Yes, build-time | Low |
| `core/libs/prx/libc` | PS5 libc compatibility | Heap, strings, stdio, filesystem, process/runtime functions | `GuestHeap.cpp`, `GuestArena.cpp`, `Export.cpp` | Yes | High |
| `core/libs/prx/libkernel` | Kernel compatibility | Pthreads, synchronization, direct memory, files, sockets, timing | `Pthread/src/Thread.cpp`, `DirectMemory.cpp` | Yes | High |
| `libSceAgc` | High-level AGC API | Builds packets, state, shader objects, draw/dispatch structures | `Command/*`, `Dcb*`, `Shader/*` | Yes for graphics games | High |
| `libSceAgcDriver` | AGC execution backend | Decodes PM4/AGC commands and drives Vulkan | `Execution/src/Driver/*`, `VulkanDevice.cpp`, `Graphics/*` | Yes for graphics | Critical |
| `core/shader/recompiler` | RDNA shader translation | RDNA ISA → IR → SPIR-V | `Recompiler.cpp`, `RdnaDecoder/*`, `Translation/*`, `SpirvBackend/*` | Yes for shaders | Critical |
| `libSceVideoOut` | Presentation/input event integration | SDL window, flip queue, vblank, presentation threads | `VideoOutDriver.cpp`, `Output.cpp` | Yes | High |
| `libScePad` | Controller compatibility | SDL controller state → PS5 pad structures | `PadState.cpp`, `PadInput.hpp` | Usually | Medium |
| `libSceAudioOut` | Audio output | Mixes/queues audio through SDL | `AudioOut.cpp`, `AudioOut2Context.cpp` | Game-dependent | Medium |
| `libSceAudiodec` | Audio decode | FFmpeg-backed decoding | `Codecs.cpp` | Game-dependent | Medium |
| `libSceAvPlayer` | Video playback | FFmpeg-based media playback | `src/*` | Game-dependent | Medium |
| `core/Decoder` | JPEG/PNG decoding | Image compatibility functions | `Jpeg.cpp`, `Png.cpp` | Game-dependent | Low |
| `3rdparty` | External dependencies | SDL, Vulkan headers, FFmpeg, FreeType, SPIR-V tooling | Various | Build/runtime | Depends |

---

# 3. Architecture

```text
                 PS5 GAME
                     │
                     ▼
              PS5 x86-64 ELF
                     │
                     ▼
              AnyPS5 Relinker
                     │
       ┌─────────────┼─────────────┐
       ▼             ▼             ▼
 ELF parser      NID resolver    Codegen
       │             │             │
       └─────────────┼─────────────┘
                     ▼
        Linux ELF or Windows PE image
                     │
                     ▼
       Host dynamic loader / Windows loader
                     │
       ┌─────────────┼─────────────┐
       ▼             ▼             ▼
   Game CPU       PRX imports     Guest modules
   code           `.prx` files    `sce_module`
       │             │             │
       ▼             ▼             ▼
 Host x86-64     libc/kernel/     Native host
 CPU             Sce libraries   shared libraries
                     │
      ┌─────────────┼─────────────┬──────────────┐
      ▼             ▼             ▼              ▼
   Memory        Threads       Video/Input      Audio
      │             │             │              │
      ▼             ▼             ▼              ▼
 mmap/VirtualAlloc std::thread   SDL/Vulkan      SDL/FFmpeg
                     │
                     ▼
              libSceAgcDriver
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
    AGC/PM4 execution       Shader recompiler
        │                         │
        ▼                         ▼
    Vulkan resources       RDNA ISA → IR → SPIR-V
        │                         │
        └────────────┬────────────┘
                     ▼
              Vulkan driver
                     │
                     ▼
                Host GPU
```

**FACT:** The CPU path is native execution. There is no general-purpose guest CPU interpreter or JIT in this repository.

**FACT:** GPU work is not passed directly as PS5 commands to the host GPU. AGC command buffers are decoded and reconstructed into Vulkan operations.

**FACT:** Shader binaries are recompiled from AMD RDNA-style ISA to SPIR-V.

---

# 4. Startup Flow

## Actual entry point

`core/relinker/main.cpp:30`

```cpp
int main(const int argc, char* argv[])
```

This is the **relinker tool**, not the eventual game executable.

The converted game executable has no AnyPS5 runtime `main()` in this repository. Its original game entry point is preserved and invoked by the generated loader stub.

## Relinker call graph

```text
main()
├── Cli::ParseArgs()
├── FileReader::Read()
├── optional Codegen::MakeAmd64OnlyConverter()->Convert()
├── Relinker::ElfReader
├── Relinker::RelinkerPipeline::Relink()
│   ├── ReadProgramHeaders()
│   ├── ReadDynamicTags()
│   ├── extractRela()
│   ├── syscall scanner
│   ├── unused NID filtering
│   ├── PLT compaction
│   ├── SysVDynamicSectionBuilder::BuildDynamicSection()
│   └── CallSiteResolver::ResolveCallSites()
├── GuestModuleBuilder::Build()
│   ├── GuestImageReader::Read()
│   ├── guest ELF validation
│   ├── guest export/import collection
│   ├── dependency ordering
│   └── GuestModuleWriter::WriteLinux/WriteWindows()
├── LinuxElfPatcher::Patch()
│   ├── append dynamic string table
│   ├── append dynamic symbol table
│   ├── append RELA tables
│   ├── append dynamic segment
│   ├── build entry stub
│   ├── optional AMD-only trampolines
│   ├── add ELF interpreter
│   └── rewrite program-header layout
├── writes converted executable
└── optional Cli::Autorun()
```

## Execution transition

`LinuxElfPatcher::Patch()`:

1. Changes the ELF type to `ET_DYN`.
2. Removes PS5 section-header metadata.
3. Appends host-compatible dynamic strings, symbols, and relocation tables.
4. Adds `DT_NEEDED` entries for host `.prx` libraries.
5. Adds `DT_RUNPATH`.
6. Builds an entry stub.
7. Changes `e_entry` to the stub.
8. Adds `/lib64/ld-linux-x86-64.so.2` as the interpreter.
9. Writes a valid host ELF layout.

`EntryStubBuilder::BuildEntryStub()` emits:

```text
mov rdi, rsp
and rsp, 0xfffffffffffffff0
xor rsi, rsi
call original_entry
ud2
```

**FACT:** The exact transition to native execution is the host loader invoking the generated entry stub, which then calls the original PS5 executable entry point.

**FACT:** The original code is not translated into an IR and re-emitted for CPU execution.

---

# 5. Executable/ELF Flow

## Input format

The main executable must be:

- ELF64
- little-endian
- x86-64
- PS5-specific dynamic metadata
- not a SELF container

`ElfReader::ReadHeader()` rejects SELF magic:

```cpp
0x4f 0x15 0x3d 0x1d
```

It then verifies ELF magic and reads the ELF64 header manually.

## Parsed structures

`core/relinker/relinker/src/parsing/ElfReader.cpp` reads:

- ELF header
- program headers
- section headers
- dynamic tags
- PT_LOAD segments
- PT_DYNAMIC
- virtual-address-to-file-offset mappings

`RelinkerPipeline::Relink()` identifies:

- executable PT_LOAD segments
- PT_DYNAMIC
- `DT_STRTAB`
- `DT_SYMTAB`
- `DT_RELA`
- `DT_JMPREL`
- `DT_PLTGOT`
- `DT_NEEDED`
- PS5 import-module tag `0x61000045`

## Relocation types

The relinker recognizes:

- `R_X86_64_64`
- `R_X86_64_GLOB_DAT`
- `R_X86_64_JUMP_SLOT`
- `R_X86_64_32`
- `R_X86_64_RELATIVE`

Unsupported relocation forms are rejected by `ValidationPolicy`.

## NID representation

PS5 imports are represented as symbol names/NIDs in the dynamic symbol table. The relinker converts them into host dynamic symbols while preserving the symbol name after stripping any `#` suffix.

`SysVDynamicSectionBuilder::BuildDynamicSection()` creates:

- host `.dynstr`
- host `.dynsym`
- `.rela.dyn`
- `.rela.plt`
- `DT_NEEDED` entries
- import-module mappings

## Code rewriting

There are two forms of rewriting:

1. **Normal execution:** no CPU code rewriting; x86-64 code remains intact.
2. **`--to-intel`:** AMD-only instructions are rewritten or replaced by trampolines.

The converter handles AMD-specific instruction families such as:

- SSE4a
- SHA1/SHA256 instructions
- `CLZERO`
- reciprocal instructions

`LinuxElfPatcher::_appendTrampoline()` appends replacement bodies and patches the original site to a relative jump.

---

# 6. Relinker

## Main relinker function

`core/relinker/relinker/src/pipeline/RelinkerPipeline.cpp:40`

```cpp
RelinkResult RelinkerPipeline::Relink(const std::vector<std::uint8_t>& sourceElf)
```

### Caller

`core/relinker/main.cpp`

### Callees

- `ElfReader::ReadProgramHeaders()`
- `ElfReader::ReadDynamicTags()`
- `ElfReader::TranslateVirtualAddress()`
- syscall scanner
- unused NID filter
- `SysVDynamicSectionBuilder`
- `CallSiteResolver`

### Input

Raw PS5 executable bytes.

### Output

`RelinkResult` containing:

- original program headers
- rebuilt dynamic section
- GOT address
- call registry entries
- binary patches

## NID filtering

Three modes exist:

- `unused-filter=0`: disabled
- `unused-filter=1`: preserve PLT, filter non-PLT references
- `unused-filter=2`: strict filtering and PLT compaction

Strict filtering performs code-flow analysis through:

- entry point collection
- CFG construction
- GOT access indexing
- relative relocation indexing
- EH-frame parsing
- PLT compaction

This is both a startup optimization and a correctness-sensitive area.

## Syscall safety

`SyscallScanner.cpp` disassembles code and rejects:

- `syscall`
- `int 0x80`
- `sysenter`
- `sysret`

The reason is architectural: a PS5 executable must not execute raw guest/system-specific syscall instructions against the host kernel.

---

# 7. ABI/API/PRX

## PRX architecture

Each system library is built as a shared host library with suffix `.prx`.

The root CMake logic:

- builds `libc.prx`
- builds other PRX libraries
- links PRX libraries against `libkernel` and `libc`
- runs `nid_patcher`
- creates patched output libraries

On Windows, `APS5_VABI` is defined as:

```cpp
#define APS5_VABI __attribute__((sysv_abi))
```

This preserves the PS5/System V calling convention when the host toolchain otherwise uses the Microsoft x64 ABI.

## Example API mappings

| PS5 API | AnyPS5 implementation | Host resource | Hardware effect |
|---|---|---|---|
| `scePthreadCreate` | `libkernel/Pthread/src/Thread.cpp` | `std::thread` or `_beginthreadex` | Host CPU thread |
| `sceKernelAllocateDirectMemory` family | `libkernel/DirectMemory/DirectMemory.cpp` | `mmap`, `memfd_create`, `VirtualAlloc`, file mappings | Host virtual memory |
| `sceVideoOutOpen` | `libSceVideoOut/src/Output.cpp` + `VideoOutDriver.cpp` | SDL window and presenter threads | Window/swapchain |
| `sceVideoOutSubmitFlip` | `VideoOutDriver::SubmitFlip()` | AGC flip packet → Vulkan presentation | Present queue and vblank timing |
| `scePadReadState` | `libScePad/Export.cpp`, `PadState.cpp` | SDL controller state | CPU-visible input structure |
| `sceAudioOutOutput` | `libSceAudioOut/src/AudioOut.cpp` | SDL queued audio | Host audio backend |
| `sceAgcCreateShader` | `libSceAgc/Shader/src/CreateShader.cpp` | Shader registration/recompiler request | Later SPIR-V compilation |
| AGC DCB submit | `libSceAgcDriver/Submit/src/Dcb.cpp`, driver | PM4 packet processing | Vulkan command generation |
| `sceKernelOpen`/file functions | libc/kernel filesystem implementations | POSIX/Win32 file I/O | SSD/HDD access |

## ABI details

**FACT:** Imported functions are dynamically linked through host ELF relocation entries. They are not called through a generic RPC layer.

**FACT:** Structures are manually recreated in `core/libs/SceTypes.hpp` and library-specific headers.

**FACT:** Many functions intentionally throw `std::runtime_error` for unsupported or invalid states. The project’s stated policy is that unsupported states terminate the process.

**FACT:** The compatibility layer contains many complete, partial, and intentionally no-op implementations.

### Implemented

- libc/string/math/runtime support
- pthreads and synchronization
- direct memory
- basic video output
- SDL controller input
- audio output
- substantial AGC/AGC driver functionality
- many graphics and shader operations

### Partially implemented or behaviorally simplified

- advanced dialog APIs
- online/network services
- trophy behavior
- audio propagation
- HMD
- some video output modes
- some controller features
- portions of AV playback
- portions of SaveData and system services

### Explicitly unimplemented

Searches for `NotImplemented_nid_no_patch`, `TranslateMemoryInstruction not implemented`, and unsupported RDNA opcodes reveal numerous deliberately missing paths.

The technical debt document is a more authoritative list than the README for these areas.

---

# 8. Memory

## Memory model

```text
PS5 virtual address
        │
        ▼
GuestArena / direct-memory allocator
        │
        ├── Linux: mmap / memfd / MAP_FIXED_NOREPLACE
        └── Windows: VirtualAlloc / file mapping
        │
        ▼
Host virtual address range
        │
        ▼
GuestMemory tracking
        │
        ├── CPU reads/writes
        ├── GPU visibility
        ├── write generations
        ├── dirty/write-watch tracking
        └── synchronization with Vulkan resources
```

## CPU memory

`GuestHeap.cpp` implements:

- 16-byte minimum alignment
- size classes for small allocations
- 1 MiB spans
- large allocations rounded to 64 KiB
- freelists
- a large-block cache
- optional cache limit through `APS5_HEAP_CACHE_MIB`

The large allocation cache is a deliberate performance optimization. The source comment states that decommitting and re-touching large temporary allocations caused page faults and TLB shootdowns.

## Direct memory

`DirectMemory.cpp` implements:

- aligned mappings
- fixed mappings
- protection changes
- direct-memory backing
- Linux `memfd_create`
- Windows section objects
- guest virtual address arena integration

## GPU memory

Graphics resources use:

- `Graphics::Buffer`
- `Graphics::DeviceBuffer`
- `Graphics::BufferPool`
- host-visible and device-local Vulkan memory
- mapped upload buffers
- command-buffer copies
- guest-memory write tracking

Relevant files:

- `Graphics/src/Resources.cpp`
- `Graphics/src/BufferPool.cpp`
- `Graphics/src/GuestBufferMemory.cpp`
- `Execution/src/GuestMemory.cpp`
- `Graphics/src/ShaderResources.cpp`

## Copies

Copies can occur through several paths:

- CPU `GuestMemory::Read`/`Write`
- mapped Vulkan upload memory
- `vkCmdCopyBuffer`
- `vkCmdCopyBufferToImage`
- `vkCmdCopyImageToBuffer`
- GPU detiling and retile operations
- color-target transfer
- texture upload and refresh

**INFERENCE:** Zero-copy is possible for some buffer/device-address paths, but not universal. Tiled render targets, texture detiling, host-visible staging, and readback paths necessarily introduce copies.

**HYPOTHESIS:** Texture-heavy workloads may be limited by repeated write-watch scans and detiling rather than raw Vulkan bandwidth.

## Synchronization

`GuestMemory::GpuMutex()` is a major global serialization point. It protects:

- resource creation
- command recording
- guest memory tracking
- GPU write visibility
- deferred labels
- buffer copies
- texture refresh

This is a likely high-value profiling point.

---

# 9. Threading

## Mapping

```text
PS5 pthread API
       │
       ▼
scePthreadCreate()
       │
       ├── Linux: std::thread
       └── Windows: _beginthreadex
       │
       ▼
PthreadPrivate
       │
       ▼
Host scheduler / CPU core
```

`core/libs/prx/libkernel/Pthread/src/Thread.cpp:275`

```cpp
int APS5_VABI scePthreadCreate(...)
```

## Properties

`PthreadPrivate` stores:

- host thread identity
- guest affinity mask
- guest priority
- stack metadata
- join/detach state
- return value
- lifecycle state
- thread name

On Linux, guest threads use `std::thread`. On Windows, the implementation uses `_beginthreadex` to control stack size and host startup.

## Important limitations

**FACT:** Guest priority and affinity are stored, but the source does not generally apply them to Linux host scheduling.

**FACT:** VideoOut owns dedicated presentation and vblank `std::jthread`s.

**FACT:** The AGC driver has queue workers and optional affinity logic for Windows job-worker threads.

**FACT:** Vulkan work is coordinated through a GPU mutex, queue state, recorder, and timeline semaphore support.

## Contention risks

Likely contention locations:

- `GuestMemory::GpuMutex()`
- `VideoOutConfig::mutex`
- flip queue mutex
- shader source-entry mutex
- shader disk-cache mutex
- descriptor cache/pipeline cache locks
- guest heap size-class locks
- large allocation cache lock

**INFERENCE:** The project uses several carefully designed lock-avoidance paths, including shader resource capture outside the GPU mutex and timeline semaphores to avoid waiting while holding GPU serialization.

---

# 10. CPU Execution

## Execution model

The PS5 title is compiled for x86-64. AnyPS5 preserves that code.

```text
PS5 machine code
       │
       ├── ordinary x86-64 instructions → execute directly
       │
       └── AMD-only instructions with --to-intel
                │
                ├── in-place lowering
                └── out-of-line trampoline
```

The host CPU therefore needs:

- x86-64 compatibility
- System V ABI compatibility
- required SIMD instructions
- appropriate handling of TLS/unwind/runtime behavior

## AMD-only conversion

The codegen subsystem recognizes AMD-only instructions and either:

- keeps them
- lowers them in place
- replaces them with a jump to a generated stub

The output reports each conversion.

**FACT:** `--to-intel` is not a CPU emulator. It is a static binary patching pass.

## CPU bottleneck candidates

- AGC PM4 packet decoding
- draw/dispatch lookup and cache validation
- guest write-watch scanning
- shader frontend compilation
- SPIR-V emission
- descriptor/resource materialization
- memory copies and detiling fallback
- dynamic allocations in graphics resource construction
- global GPU mutex wait time

---

# 11. Graphics

## Graphics path

```text
Game AGC calls
      │
      ▼
libSceAgc packet/state construction
      │
      ▼
libSceAgcDriver::Submit()
      │
      ▼
PM4/DCB packet decode
      │
      ├── draw path
      ├── dispatch path
      ├── copy/fill path
      ├── synchronization path
      └── presentation path
      │
      ▼
Graphics resource/state reconstruction
      │
      ▼
Vulkan command recorder
      │
      ▼
vkQueueSubmit
```

Important driver files:

- `Execution/src/Driver/Packets/PacketExecution.cpp`
- `Execution/src/Driver/Draw/Draw.cpp`
- `Execution/src/Driver/Dispatch/Dispatch.cpp`
- `Execution/src/Driver/Memory/BufferCopy.cpp`
- `Execution/src/Driver/Queues/Submission.cpp`
- `Execution/src/Driver/Presentation.cpp`
- `Graphics/src/Pipeline.cpp`
- `Graphics/src/ShaderResources.cpp`
- `Graphics/src/Texture.cpp`
- `Graphics/src/Draw.cpp`

## Draw path

The draw path reconstructs:

- vertex/index buffers
- shader stages
- interpolator metadata
- render targets
- depth/stencil state
- descriptor/resource state
- indirect draw arguments
- pipeline variants

It has explicit caches and timing counters.

## Dispatch path

The dispatch path supports:

- direct dispatch
- indirect dispatch
- compute shader compilation
- resource capture
- dispatch recipe caching
- data-hit validation
- Vulkan dispatch recording

---

# 12. Shader Recompiler

## Shader pipeline

```text
RDNA shader bytes
       │
       ▼
RdnaInstructionDecoder
       │
       ▼
ControlFlow::GraphBuilder
       │
       ▼
Structurizer
       │
       ▼
InstructionTranslator
       │
       ▼
IR program
       │
       ├── SSA construction
       ├── constant folding
       ├── dead-code elimination
       ├── read-lane elimination
       ├── masked-select elimination
       ├── SRT/resource analysis
       └── resource tracking
       │
       ▼
Resource specialization
       │
       ▼
Binding allocation
       │
       ▼
SpirvEmitter
       │
       ▼
optional SPIRV-Tools validation/optimization
       │
       ▼
VkShaderModule / Vulkan pipeline
```

## Entry points

`Recompiler.cpp:94`

```cpp
IrProgram PrepareResourceProgram(const RecompileRequest& request)
```

`Recompiler.cpp:307`

```cpp
CompiledVariant compileVariant(...)
```

`Recompiler.cpp:701`

```cpp
std::shared_ptr<const RecompileResult> Recompile(...)
```

## ISA

**FACT:** The decoder is specifically named `RdnaDecoder`. It handles AMD RDNA-style instruction families:

- scalar operations
- vector ALU
- memory operations
- image operations
- LDS/shared-memory operations
- control flow
- interpolation
- exports
- atomics

## Intermediate representation

The IR consists of:

- `IrProgram`
- `IrBlock`
- `IrOpcode`
- `IrValue`
- guest register abstractions
- shader metadata
- control-flow metadata
- resource metadata

## Control flow

The frontend:

1. Decodes instructions.
2. Builds a CFG.
3. Structurizes the CFG.
4. Translates instructions into IR.
5. Runs SSA and optimization passes.
6. Emits structured SPIR-V control flow.

## Shader caching

There are several cache levels:

1. Source-entry cache keyed by shader code hash and code contents.
2. Variant cache keyed by layout/resource specialization.
3. Result memo cache, up to 256 entries.
4. Disk cache with versioned serialized SPIR-V and metadata.
5. Vulkan pipeline cache.

`ShaderDiskCache.cpp` runs a detached writer thread and records hit/miss/read/write statistics.

**FACT:** Shader compilation can be synchronous on first use.

**FACT:** Disk cache persistence exists, but host Vulkan pipeline creation can still be a separate cost.

**INFERENCE:** First-use shader stutter is possible when all of the following happen together:

- source plan creation
- RDNA decoding
- IR optimization
- SPIR-V emission
- Vulkan shader-module creation
- graphics/compute pipeline creation

---

# 13. Vulkan

## Instance and device creation

`VulkanDevice::VulkanDevice()` begins at `VulkanDevice.cpp:566`.

It:

1. Dynamically loads `libvulkan.so.1` or `vulkan-1.dll`.
2. Resolves `vkGetInstanceProcAddr`.
3. Creates a Vulkan 1.1 instance.
4. Adds SDL-required instance extensions when presenting.
5. Enumerates physical devices.
6. Chooses the highest-ranked discrete/integrated/virtual GPU.
7. Requires a queue family with both graphics and compute.
8. Requires swapchain support for presentation.
9. Queries optional features/extensions.
10. Creates the logical device.
11. Creates a command pool.
12. Initializes buffer, texture, descriptor, pipeline, recorder, detiler, and presentation subsystems.

## Device ranking

```text
Discrete GPU       rank 3
Integrated GPU     rank 2
Virtual GPU        rank 1
Other              rank 0
```

The selected queue family must support:

- graphics
- compute
- presentation when a window is used

## Required or strongly required features

The constructor requires or uses:

- Vulkan 1.1
- sampler anisotropy
- BC texture compression
- `VK_KHR_shader_float_controls`
- signed-zero/Inf/NaN preservation for float32
- buffer device address
- 8-bit storage
- optional descriptor indexing
- optional shader clock
- optional fragment shader barycentric
- optional mesh shader
- optional timeline semaphores
- optional subgroup-size control
- optional shader atomic extensions
- optional pipeline executable properties

## Command buffers and submission

The graphics `Recorder` collects Vulkan commands. `Graphics/src/Resources.cpp` contains `CommandBatch::Submit()` and calls:

```cpp
vkQueueSubmit(...)
```

The project also uses:

- command pools
- command-buffer reset
- fences
- semaphores
- timeline semaphores when available
- recorded batch serials
- retire/reap logic
- presentation-specific command buffers

## Presentation

`Driver::Present()` is in:

`core/libs/prx/libSceAgcDriver/Execution/src/Driver/Presentation.cpp:26`

The presenter:

- ensures a Vulkan window/surface
- acquires swapchain images
- records transfer/scaling operations
- submits presentation work
- queues present
- tracks frame timing
- invokes `gpuReady` once GPU work is prepared

`VideoOutDriver::processFlip()` waits for vblank and then invokes AGC presentation.

## GPU synchronization risks

Potential stalls include:

- `vkWaitForFences`
- `vkQueueWaitIdle`
- timeline semaphore waits
- `GuestMemory::GpuMutex`
- GPU write flushes
- CPU readbacks
- swapchain acquire/present
- texture detile completion
- buffer-copy fallback

---

# 14. Input

## Input path

```text
SDL event queue
      │
      ▼
VideoOutDriver::presentLoop()
      │
      ├── PadInput::HandleEvent()
      ├── MouseInput
      └── KeyboardInput
      │
      ▼
Pad::PublishState()
      │
      ▼
scePadReadState()
      │
      ▼
PS5 PadData structure
      │
      ▼
Game
```

`VideoOutDriver::presentLoop()` calls:

```cpp
SDL_PollEvent(&event)
padInput.HandleEvent(...)
padInput.Update()
```

`PadInput` supports:

- SDL game controllers
- analog sticks
- triggers
- touchpad
- sensors
- rumble
- light bar
- trigger effects
- keyboard/mouse mappings
- hotplug-oriented controller opening logic

`PadState.cpp` adds:

- quaternion orientation integration
- accelerometer/gyro fusion
- touch ID assignment
- trigger state encoding
- vibration state tracking

## Latency sources

- event polling occurs in the presentation thread
- controller state is published from that thread
- game reads state later through `scePadReadState`
- sensor fusion happens while holding `stateMutex`
- output effects are refreshed periodically

**HYPOTHESIS:** Input latency is likely dominated by the game’s polling cadence and the 10 ms presenter wait interval when no flip request is pending, rather than SDL controller access itself.

---

# 15. Audio

## Audio path

```text
Game audio API
      │
      ▼
libSceAudioOut
      │
      ├── format conversion
      ├── port queue
      ├── mixing
      └── SDL_QueueAudio
      │
      ▼
SDL audio backend
      │
      ▼
Host audio device
```

`AudioOut.cpp` implements:

- port open/close
- audio format validation
- SDL device creation
- resampling/format conversion using SDL audio conversion
- queue depth handling
- output timing
- volume/mix controls

`AudioOut2Context.cpp` implements:

- multiple ports
- grain-based mixing
- pad speaker routing
- queue advancement
- main output and controller output devices

`libSceAudiodec` uses FFmpeg codecs. `libSceAjm.native` also uses FFmpeg for MP3/Opus decoding.

## Audio bottlenecks

- SDL audio queue depth
- conversion allocation/copying
- grain mixing
- blocking queue waits
- FFmpeg decode cost
- audio device scheduling

`libSceAudioIn` contains a polling loop that sleeps in 1 ms increments while waiting for queued capture bytes.

---

# 16. Filesystem/I/O

## Path

```text
Game filesystem API
      │
      ▼
libc/libkernel filesystem layer
      │
      ▼
POSIX syscalls or Win32 APIs
      │
      ▼
Host filesystem
      │
      ▼
SSD/HDD
```

Relevant components include:

- `libc/src/Filesystem.cpp`
- `libc/src/FileAndHeap.cpp`
- `libc/include/FileStream.hpp`
- `libkernel/File`
- directory wrappers
- guest path handling
- SaveData implementations
- AV player source loading

**FACT:** The relinker emits a runtime layout with:

```text
output executable
libs/
app0/
    guest modules
```

The converted executable uses `$ORIGIN`-based runpaths on Linux.

**UNKNOWN / NOT VERIFIED FROM SOURCE:** A general asynchronous asset streaming subsystem comparable to a console kernel I/O scheduler was not identified. Individual APIs may provide asynchronous semantics, but a unified I/O scheduler is not evident.

Potential costs:

- asset decompression
- repeated file reads
- file-to-host-buffer copies
- SaveData serialization
- FFmpeg demux/decode
- directory enumeration

---

# 17. Frame Execution

A source-grounded frame timeline is:

```text
Game thread
│
├── PS5 API calls
├── AGC command-buffer construction
├── sceAgcDriverSubmitDcb()
│
├── AGC queue worker
│   ├── packet decode
│   ├── state reconstruction
│   ├── resource capture
│   ├── shader lookup/recompile
│   ├── descriptor/resource preparation
│   ├── Vulkan command recording
│   └── queue submission
│
├── sceVideoOutSubmitFlip()
│
├── presentation queue
│   ├── vblank wait
│   ├── SDL event polling
│   ├── surface/swapchain operations
│   ├── GPU presentation
│   └── flip completion notification
│
└── next frame
```

## Likely classification

| Area | Classification | Evidence |
|---|---|---|
| Game simulation | CPU-bound or game-dependent | Native game code |
| PM4/AGC decode | CPU-bound | Host packet interpreter |
| Shader first use | CPU-bound plus driver-bound | Recompiler and pipeline creation |
| Descriptor/resource validation | CPU-bound | `ShaderResources`, capture validation |
| Texture detiling | GPU-bound or copy-bound | Compute detiler and staging paths |
| Render workload | GPU-bound | Vulkan graphics pipelines |
| Write-watch scans | Memory/CPU-bound | `GuestMemory::CollectWrites`, compare paths |
| GPU mutex waits | Synchronization-bound | Global serialized resource/recording path |
| Vblank pacing | Presentation-bound | `vblankLoop`, FIFO swapchain |
| Audio decode | CPU-bound | FFmpeg codecs |
| Asset streaming | I/O-bound | Filesystem/AV APIs |

These classifications are not universal per game. They must be measured with the instrumentation strategy below.

---

# 18. Performance Bottlenecks

| Priority | Location | Problem | Why Expensive | Evidence | Proposed Optimization | Risk |
|---|---|---|---|---|---|---|
| Critical | `Execution/src/GuestMemory.cpp`, `Graphics/src/ShaderResources.cpp` | Global GPU mutex | Serializes resource builds, uploads, command recording, write tracking | Many paths explicitly lock `GuestMemory::GpuMutex()` | Split immutable lookup from mutation; reduce lock hold duration | High correctness risk |
| Critical | `shader/recompiler/Recompiler.cpp` | First-use shader compilation | RDNA decode, CFG, IR, optimization, SPIR-V emission are synchronous | `RecompileImpl()` performs full pipeline before return | Precompile known shaders or compile on worker thread with readiness fences | High |
| High | `Graphics/src/Pipeline.cpp` | Vulkan pipeline creation | `vkCreateGraphicsPipelines`/compute pipeline creation can block | Direct calls in `Pipeline.cpp` | Pipeline-library or asynchronous pipeline build | Medium |
| High | `Graphics/src/ShaderResources.cpp` | Repeated write-watch and resource validation | Scans and compares guest memory each draw/dispatch | `CollectWrites`, `UnchangedSince`, `CompareMapped` | Improve dirty-range granularity and cache hit paths | High |
| High | `Execution/src/Driver/Draw/*` | Draw cache misses | Misses repeat state decode, shader/resource preparation | Draw lookup/cache subsystem exists | Instrument miss reasons and improve key normalization | Medium |
| High | `Execution/src/Driver/Dispatch/*` | Dispatch cache misses | Repeats shader/resource preparation | Dispatch cache and recipe code | Add stable per-program instrumentation and cache statistics | Medium |
| High | `Graphics/src/TextureDetiler.cpp` | Repeated detile/retile | Tiled guest images require compute conversion and copies | Explicit detiler dispatch and staging | Retain resident detiled images and track exact written ranges | High |
| High | `Graphics/src/Draw.cpp` | CPU readback of color/depth data | Readback and CPU conversion can stall GPU | `vkCmdCopyImageToBuffer`, `GuestMemory::Write` | GPU-side conversion/readback and delayed completion | High |
| Medium | `Graphics/src/Resources.cpp` | Frequent allocation/free of Vulkan buffers | Even with buffer pools, misses create Vulkan objects | `BufferPool` and `Buffer` constructors | Tune pool tiers and eviction based on workload | Medium |
| Medium | `Graphics/src/ShaderResources.cpp` | Descriptor set allocation | Descriptor cache allocates and frees sets | `DescriptorCache::Allocate` | Per-frame pools or descriptor indexing where available | Medium |
| Medium | `ShaderDiskCache.cpp` | Disk-cache misses or oversized entries | First-run recompilation and filesystem reads | Explicit hit/miss counters | Prewarm cache, compress metadata, batch writes | Low |
| Medium | `libc/src/GuestHeap.cpp` | Large cache memory pressure | 4 GiB default cache may retain substantial memory | `APS5_HEAP_CACHE_MIB` | Tune cache per game/hardware and expose usage counters | Low |
| Medium | `libSceAudioOut/src/AudioOut.cpp` | SDL conversion/copy | Format conversion occurs before queueing | `SDL_BuildAudioCVT`, `SDL_ConvertAudio` | Match output format when possible | Low |
| Low | `VideoOutDriver::presentLoop()` | 10 ms event wait | Adds polling delay when no flip request exists | `wait_for(10ms)` | Event-driven wakeups or shorter adaptive interval | Low |
| Low | `CallSiteResolver` | Startup instruction scan | Repeated scan for imported call sites | Cached instruction map | Persist registry or avoid scans unless requested | Low |

The most defensible first performance target is **measurement and reduction of shader/draw preparation overhead**, because the project already contains caches, timing phases, and diagnostics around that path.

---

# 19. Instrumentation

## CPU

Add instrumentation around:

- `RelinkerPipeline::Relink`
- `GuestModuleBuilder::Build`
- `PrepareResourceProgram`
- `compileVariant`
- `materializeResult`
- `Driver::lookupDraw`
- `Driver::compileDrawStage`
- `Dispatch.cpp` cache lookup/compile paths
- `GuestMemory::CollectWrites`
- `GuestMemory::CompareMapped`
- `BufferPool::Take/Put`
- `DescriptorCache::Allocate/Free`

Use:

- `std::chrono::steady_clock`
- per-thread counters
- phase timing already used by `PerformanceTimer`
- allocation counters in `GuestHeap`
- lock wait durations

## GPU

Instrument:

- `Graphics::Recorder::Submit`
- `CommandBatch::Submit`
- `VulkanDevice::FinishPresent`
- `VulkanDevice::QueuePresent`
- `Driver::Present`
- `vkQueueSubmit`
- `vkWaitForFences`
- timeline semaphore waits
- pipeline creation
- shader-module creation
- detiler dispatches

Use:

- Vulkan timestamp queries
- `VK_KHR_pipeline_executable_properties`
- GPU timestamp around draw/dispatch batches
- submission serials
- fence completion latency

## Memory

Record:

- guest allocation count/bytes
- large-cache hit/miss
- `GuestMemory::Read/Write` bytes
- CPU-to-GPU copies
- GPU-to-CPU copies
- detile bytes
- upload bytes
- readback bytes
- mapped-memory lifetime
- buffer-pool hit/miss

## I/O

Record:

- open/read/close latency
- bytes read
- decompression time
- FFmpeg packet/decode time
- asset path
- synchronous versus asynchronous call path

## Frame metrics

Collect:

- game CPU frame time
- AGC decode time
- resource preparation time
- shader compile time
- Vulkan recording time
- queue-submit time
- GPU execution time
- present wait time
- vblank wait time
- input poll time
- frame queue depth

Existing `PerformanceTimer`, `APS5_PROFILE_DRAW`, shader-disk-cache reports, and AGC diagnostic counters should be reused instead of creating a disconnected profiling system.

---

# 20. Benchmark Strategy

## Reproducibility

For each test:

1. Pin AnyPS5 commit and build flags.
2. Record GPU driver and Vulkan version.
3. Delete or preserve shader cache explicitly.
4. Run the same game scene/save state.
5. Warm up for 60–120 seconds.
6. Measure at least 60 seconds.
7. Repeat three times.
8. Record average, 1% low, 0.1% low, median, and frame-time variance.

## Required runs

| Run | Purpose |
|---|---|
| Cold shader cache | Measures frontend and pipeline compilation |
| Warm shader cache | Measures steady-state runtime |
| `APS5_NO_RESULT_MEMO=1` | Measures result memoization benefit |
| `APS5_NO_TIMELINE=1` | Measures timeline semaphore benefit |
| `APS5_NO_DATA_HITS=1` | Measures data-hit cache benefit |
| `APS5_PROFILE_DRAW=1` | Breaks down draw phases |
| `APS5_PIPELINE_STATS=1` | Captures driver pipeline statistics |
| Different `APS5_HEAP_CACHE_MIB` | Tests guest heap reuse |

## CPU-bound versus GPU-bound

Use:

- GPU utilization
- CPU core utilization
- CPU frame time
- GPU timestamp frame time
- resolution scaling

Interpretation:

- lowering resolution improves FPS substantially → likely GPU-bound
- lowering resolution does little, one CPU core saturated → likely CPU/driver-bound
- cold run stutters, warm run stabilizes → shader/pipeline-bound
- GPU timestamps are short but CPU frame time is high → CPU preparation or synchronization-bound
- long fence/timeline waits → GPU backlog or synchronization-bound

---

# 21. Hardware Optimization

The source already exposes hardware-sensitive areas:

## CPU

Map:

```text
CPU cache/SIMD/scheduler
        ↓
native game code, AGC decode, shader frontend, write tracking
        ↓
CPU bottleneck
        ↓
affinity, compiler flags, cache locality, lock reduction
```

Important variables:

- physical cores
- SMT behavior
- hybrid P/E-core topology
- AVX/SSE availability
- L1/L2/L3 cache
- memory latency
- Linux scheduler or Windows scheduler

## GPU

Map:

```text
GPU architecture
        ↓
Vulkan driver + subgroup width + shader compiler
        ↓
SPIR-V execution, detiling, pipelines, presentation
        ↓
GPU bottleneck
```

Relevant source decisions:

- discrete GPU preference
- subgroup size
- optional wave32 support
- barycentric support
- descriptor indexing
- shader clock
- mesh shaders
- buffer device address
- timeline semaphores
- pipeline cache

## RAM

Relevant to:

- guest arena
- shader cache metadata
- large heap cache
- texture caches
- pipeline caches
- staging allocations

## Storage

Relevant to:

- shader disk cache
- game asset streaming
- FFmpeg media
- SaveData
- guest module loading

## OS

Relevant to:

- dynamic loader
- pthread behavior
- memory mapping
- page faults
- scheduling
- Vulkan loader/driver
- filesystem latency

Hardware-specific recommendations should wait until the user provides exact hardware.

---

# 22. Contribution Opportunities

| Priority | Area | Problem | Files | Difficulty | Impact | Testing |
|---|---|---|---|---:|---:|---|
| 1 | Shader profiling | Shader compile cost is measurable but not fully exposed per stage | `Recompiler.cpp`, `ShaderDiskCache.cpp` | Medium | High | Recompiler tests + benchmark |
| 2 | Draw-cache diagnostics | Cache misses need reason-level breakdown | `Driver/Draw/*` | Medium | High | Existing draw tests |
| 3 | Dispatch-cache diagnostics | Same for compute recipes/data hits | `Driver/Dispatch/*` | Medium | High | Compute tests |
| 4 | GPU mutex profiling | Lock contention is a likely global bottleneck | `GuestMemory.*`, driver paths | Medium | High | Stress tests |
| 5 | Descriptor allocation reuse | Descriptor allocation can be expensive | `ShaderResources.cpp` | Medium | Medium | Graphics tests |
| 6 | Pipeline cache persistence | Vulkan pipeline cache lifecycle can be improved | `PipelineCache.cpp` | Medium | Medium | Visual tests |
| 7 | Texture residency tracking | Avoid repeated detile/upload when guest memory is unchanged | `TextureCache.cpp`, `ShaderResources.cpp` | High | High | Texture tests |
| 8 | Buffer pool tuning | Pool tiers and eviction are generic | `BufferPool.cpp` | Low/Medium | Medium | Buffer tests |
| 9 | Input wakeup latency | Presenter waits up to 10 ms for events | `VideoOutDriver.cpp` | Low | Low/Medium | Input tests |
| 10 | Audio conversion avoidance | Repeated SDL conversion may cost CPU | `AudioOut.cpp` | Low | Low/Medium | Audio tests |
| 11 | Relinker registry reuse | Call-site scan is repeated at conversion time | `CallSiteResolver.cpp` | Medium | Medium | Relinker tests |
| 12 | Missing shader instruction support | Many unsupported RDNA paths terminate execution | `Translation/*`, `RdnaDecoder/*` | High | High compatibility | Shader regression tests |
| 13 | Vulkan feature diagnostics | Unsupported optional features are not summarized uniformly | `VulkanDevice.cpp` | Low | Medium | Device test |
| 14 | Guest heap telemetry | Large cache behavior is configurable but not observable enough | `GuestHeap.cpp` | Low | Medium | Heap tests |
| 15 | Async shader compilation | First-use stutter remains possible | `Recompiler.cpp`, driver pipeline paths | High | High | Frame benchmark |

---

# 23. Recommended First PR

## Recommended contribution

**Add structured shader and draw preparation timing with cache-miss reason reporting.**

This is the best first serious PR because:

- the subsystem already has timing infrastructure
- it does not alter rendering semantics
- it can be tested independently
- it produces immediately useful data for upstream developers
- it can identify whether future optimization should target shader compilation, descriptor setup, resource capture, or Vulkan pipeline creation

## Problem

`APS5_PROFILE_DRAW` provides broad timing information, but the source still has several distinct cache and preparation stages:

- source-plan creation
- variant compilation
- disk-cache load
- result memoization
- resource materialization
- draw lookup
- pipeline creation
- validation

A contributor currently cannot easily correlate a frame spike with one specific miss reason.

## Existing implementation

Relevant functions:

- `PrepareResourceProgram()`
- `compileVariant()`
- `findOrCompileVariant()`
- `materializeMemoized()`
- `Driver::lookupDraw()`
- `Driver::compileDrawStage()`

## Proposed output

For each shader/draw key:

```text
shader=0x...
stage=fragment
source_hit=1
variant_hit=0
disk_hit=0
result_memo_hit=0
resource_materialize_us=...
spirv_emit_us=...
pipeline_create_us=...
draw_lookup_us=...
```

## Expected impact

No immediate FPS improvement is guaranteed. The measurable benefit is:

- reliable bottleneck identification
- better upstream issue reports
- targeted optimization decisions
- regression detection

---

# 24. Implementation Plan

## Step 1

**File:** `core/shader/recompiler/Recompiler.cpp`  
**Functions:** `PrepareResourceProgram`, `compileVariant`, `findOrCompileVariant`

Add scoped timers and counters for:

- decode/CFG
- translation
- optimization
- resource-plan construction
- SPIR-V emission
- disk-cache load/store
- variant cache hit/miss

Use the existing `APS5_PROFILE_DRAW` gate.

## Step 2

**File:** `core/shader/recompiler/Recompiler.cpp`  
**Function:** `materializeMemoized`

Record:

- result memo hit
- result memo miss
- eviction
- materialization duration

The file already maintains `ResultMemoCounters`; extend that mechanism rather than adding a second statistics system.

## Step 3

**Files:** `core/libs/prx/libSceAgcDriver/Execution/src/Driver/Draw/*`

Add miss-reason counters:

- shader source miss
- shader variant miss
- resource snapshot mismatch
- draw-key mismatch
- pipeline miss
- validation rejection
- indirect-path fallback

## Step 4

**File:** `core/libs/prx/libSceAgcDriver/Graphics/src/Pipeline.cpp`

Measure:

- shader module creation
- graphics pipeline creation
- render-pass/framebuffer setup
- pipeline cache hit/miss if available

## Step 5

**Tests**

Add unit-level counter tests where practical:

- repeated identical shader requests produce a cache hit
- changed specialization produces a variant miss
- changed resource snapshot produces a result memo miss
- disk-cache load returns a cache hit

## Step 6

**Benchmark**

Use one verified game and measure:

- cold cache
- warm cache
- with profiling enabled
- without profiling
- 60-second run
- average frame time
- 1% low
- number and duration of shader misses

## Step 7

**PR presentation**

Describe:

1. The inability to distinguish shader/resource/pipeline misses.
2. The exact new counters and timers.
3. The overhead when profiling is disabled.
4. Example output from one verified title.
5. A follow-up optimization enabled by the measurements.

---

# 25. Hardware Information Needed

Provide:

- CPU model
- physical cores / threads
- cache sizes
- GPU model
- GPU VRAM
- RAM capacity
- RAM speed and channel configuration
- storage type and model
- operating system
- kernel or Windows version
- GPU driver version
- Vulkan version
- compiler and compiler version
- CMake build type
- compiler flags
- AnyPS5 commit/version
- target game
- current average FPS
- 1% low if available
- frame-time graph if available
- shader stutter behavior
- crashes or hangs
- CPU utilization
- per-core CPU utilization
- GPU utilization
- VRAM usage
- RAM usage
- resolution and graphics settings
- whether shader disk cache is enabled
- whether `--to-intel` is used
- whether timeline semaphores are enabled
- whether pipeline statistics are enabled

---

# 26. Final Architecture Diagram

```text
                         PS5 GAME
                             │
                             ▼
                    PS5 x86-64 ELF
                             │
                             ▼
                         RELINKER
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
   ELF parser            NID resolver          Codegen
        │                    │                    │
        │                    │              AMD-only
        │                    │             instruction
        │                    │              trampolines
        └────────────────────┼────────────────────┘
                             ▼
                 Linux ELF / Windows PE
                             │
                             ▼
                   Host dynamic loader
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
      Native game      `.prx` imports      Guest modules
      x86-64 code      libc/kernel/Sce     sce_module/prx
          │                  │                  │
          └──────────────────┼──────────────────┘
                             ▼
                      Runtime compatibility
                             │
       ┌──────────────┬──────┼──────┬──────────────┐
       ▼              ▼      ▼      ▼              ▼
     CPU           Memory  Threads Video/Input    Audio
       │              │      │      │              │
       ▼              ▼      ▼      ▼              ▼
   Host x86-64     mmap   std::thread SDL/Vulkan  SDL/FFmpeg
                             │
                             ▼
                       libSceAgcDriver
                             │
                ┌────────────┴────────────┐
                ▼                         ▼
          AGC / PM4 execution       Shader recompiler
                │                         │
                ▼                         ▼
          Vulkan commands          RDNA ISA
                │                   → CFG/IR
                │                   → SPIR-V
                └────────────┬────────────┘
                             ▼
                       Vulkan device
                             │
                             ▼
                       GPU driver
                             │
                             ▼
                         Host GPU
```

---

# 27. Open Questions

These require runtime tests or game traces rather than static source inspection:

1. Which exact games exercise the highest-cost AGC paths?
2. How much time is spent under `GuestMemory::GpuMutex()` per frame?
3. What percentage of frames are draw-cache hits?
4. How frequently are shaders compiled after warm-up?
5. How often do texture resources require detile/retile?
6. How much CPU time is spent in write-watch scans?
7. Which Vulkan vendors produce the largest pipeline-creation variance for the generated SPIR-V?
8. How effective is the Vulkan pipeline cache across process launches?
9. Does asynchronous disk-cache writing interfere with asset streaming on slower storage?
10. Which guest threads would benefit from host affinity?
11. How much does `APS5_NO_TIMELINE=1` degrade frame pacing?
12. How much memory does the 4 GiB default heap cache retain for each title?
13. Are any titles relying on unimplemented raw filesystem async semantics?
14. Which unsupported shader instructions are encountered in real games?
15. What fraction of CPU execution consists of native game code versus compatibility-layer calls?
16. Which AMD-only instructions appear in target games?
17. How often does `--to-intel` produce out-of-line trampolines?
18. Are presentation stalls caused by FIFO present mode, GPU backlog, or vblank pacing?
19. Which audio paths use FFmpeg decode versus already-decoded PCM?
20. What is the practical CPU/GPU split for the user’s hardware?

The best reading order for a new contributor is:

```text
README.md
→ docs/dev/BUILD.md
→ core/relinker/main.cpp
→ RelinkerPipeline.cpp
→ LinuxElfPatcher.cpp
→ GuestModuleBuilder.cpp
→ libc / libkernel
→ libSceAgcDriver/Execution
→ libSceAgcDriver/Graphics
→ shader/recompiler/Recompiler.cpp
→ RdnaDecoder
→ Translation
→ SpirvBackend
```

The safest initial modifications are diagnostics, cache counters, timing, relinker tests, and isolated PRX behavior. The highest-impact but higher-risk work is in `GuestMemory`, shader compilation, texture residency, draw/dispatch caching, and Vulkan synchronization.