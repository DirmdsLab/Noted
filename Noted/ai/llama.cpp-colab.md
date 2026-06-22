compile dari mesin yang beda
pakai podman

isi workspace repo dari llama.cpp

https://github.com/ggml-org/llama.cpp.git


12s ❯ podman run \                                                                                                                                                       05:50
            --memory=4g \
            --memory-swap=4g \
            --cpus=12 \
            -it \
            -v $PWD:/workspace \
            nvidia/cuda:12.3.2-devel-ubuntu22.04



limit? karena pc saya memory rendah T_T

in container

    1  apt update
    2  apt install -y git cmake build-essential

/workspace/
ls
cd llama.cpp
ls
rm -rf build

find /usr/local/cuda -name "libcuda.so*"
cd /usr/local/cuda/lib64/stubs
ln -s libcuda.so libcuda.so.1
export LIBRARY_PATH=/usr/local/cuda/lib64/stubs:$LIBRARY_PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs:$LD_LIBRARY_PATH

rm -rf build
cmake -B build   -DGGML_CUDA=ON   -DGGML_NATIVE=OFF   -DCMAKE_CUDA_ARCHITECTURES="75"   -DLLAMA_BUILD_EXAMPLES=OFF
cmake --build build -j6