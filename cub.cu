/* ssbench: benchmarking of sort and scan libraries
 * Copyright (C) 2014  Bruce Merry
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <cub/cub.cuh>
#include <vector>
#include <string>
#include <cstddef>
#include <boost/utility.hpp>
#include "algorithms.h"
#include "register.h"
#include "cudautils.h"

template<typename T>
class cuda_vector : public boost::noncopyable
{
private:
    T *ptr;
    std::size_t elements;

public:
    cuda_vector() : ptr(NULL), elements(0) {}

    explicit cuda_vector(std::size_t elements)
    {
        std::size_t bytes = elements * sizeof(T);
        CUDA_CHECK( cudaMalloc(&ptr, bytes) );
        this->elements = elements;
    }

    ~cuda_vector()
    {
        if (ptr != NULL)
            cudaFree(ptr);
    }

    T *data() const { return ptr; }

    std::size_t size() const
    {
        return elements;
    }

    void swap(cuda_vector<T> &other)
    {
        std::swap(ptr, other.ptr);
        std::swap(elements, other.elements);
    }
};

template<typename T>
struct cub_double_vector : public boost::noncopyable
{
    // mutable because Current() doesn't work on const objects
    mutable cub::DoubleBuffer<T> ptrs;
    std::size_t elements;

    cub_double_vector() : ptrs(NULL, NULL), elements(0) {}
    explicit cub_double_vector(std::size_t size)
    {
        std::size_t bytes = size * sizeof(T);
        CUDA_CHECK( cudaMalloc(&ptrs.d_buffers[0], bytes) );
        CUDA_CHECK( cudaMalloc(&ptrs.d_buffers[1], bytes) );
        elements = size;
    }
    ~cub_double_vector()
    {
        if (ptrs.d_buffers[0])
            cudaFree(ptrs.d_buffers[0]);
        if (ptrs.d_buffers[1])
            cudaFree(ptrs.d_buffers[1]);
    }

    std::size_t size() const { return elements; }

    void swap(cub_double_vector<T> &other)
    {
        std::swap(ptrs, other.ptrs);
        std::swap(elements, other.elements);
    }
};

class cub_algorithm
{
private:
    void *d_temp;
    std::size_t d_temp_size;

public:
    template<typename T>
    struct types
    {
        typedef cuda_vector<T> vector;
        typedef vector scan_vector;
        typedef cub_double_vector<T> sort_vector;
    };

    template<typename T>
    static void create(cuda_vector<T> &out, std::size_t elements)
    {
        cuda_vector<T>(elements).swap(out);
    }

    template<typename T>
    static void create(cub_double_vector<T> &out, std::size_t elements)
    {
        cub_double_vector<T>(elements).swap(out);
    }

    template<typename T>
    static void copy(const std::vector<T> &src, cuda_vector<T> &dst)
    {
        CUDA_CHECK( cudaMemcpy(dst.data(), &src[0], src.size() * sizeof(T), cudaMemcpyHostToDevice) );
    }

    template<typename T>
    static void copy(const cuda_vector<T> &src, cub_double_vector<T> &dst)
    {
        CUDA_CHECK( cudaMemcpy(dst.ptrs.Current(), src.data(), src.size() * sizeof(T), cudaMemcpyDeviceToDevice) );
    }

    template<typename T>
    static void copy(const cuda_vector<T> &src, std::vector<T> &dst)
    {
        CUDA_CHECK( cudaMemcpy(&dst[0], src.data(), src.size() * sizeof(T), cudaMemcpyDeviceToHost) );
    }

    template<typename T>
    static void copy(const cub_double_vector<T> &src, std::vector<T> &dst)
    {
        CUDA_CHECK( cudaMemcpy(&dst[0], src.ptrs.Current(), src.size() * sizeof(T), cudaMemcpyDeviceToHost) );
    }

    template<typename T>
    void pre_scan(const cuda_vector<T> &src, cuda_vector<T> &dst)
    {
        CUDA_CHECK( cub::DeviceScan::ExclusiveSum(NULL, d_temp_size, src.data(), dst.data(), src.size()) );
        CUDA_CHECK( cudaMalloc(&d_temp, d_temp_size) );
    }

    template<typename T>
    void scan(const cuda_vector<T> &src, cuda_vector<T> &dst)
    {
        CUDA_CHECK( cub::DeviceScan::ExclusiveSum(d_temp, d_temp_size, src.data(), dst.data(), src.size()) );
    }

    template<typename K>
    void pre_sort(cub_double_vector<K> &keys)
    {
        CUDA_CHECK( cub::DeviceRadixSort::SortKeys(NULL, d_temp_size, keys.ptrs, keys.size()) );
        CUDA_CHECK( cudaMalloc(&d_temp, d_temp_size) );
    }

    template<typename K>
    void sort(cub_double_vector<K> &keys)
    {
        CUDA_CHECK( cub::DeviceRadixSort::SortKeys(d_temp, d_temp_size, keys.ptrs, keys.size()) );
    }

    template<typename K, typename V>
    void pre_sort_by_key(cub_double_vector<K> &keys, cub_double_vector<V> &values)
    {
        CUDA_CHECK( cub::DeviceRadixSort::SortPairs(NULL, d_temp_size, keys.ptrs, values.ptrs, keys.size()) );
        CUDA_CHECK( cudaMalloc(&d_temp, d_temp_size) );
    }

    template<typename K, typename V>
    void sort_by_key(cub_double_vector<K> &keys, cub_double_vector<V> &values)
    {
        CUDA_CHECK( cub::DeviceRadixSort::SortPairs(d_temp, d_temp_size, keys.ptrs, values.ptrs, keys.size()) );
    }

    static void finish()
    {
        CUDA_CHECK( cudaDeviceSynchronize() );
    }

    static std::string api() { return "cub"; }

    explicit cub_algorithm(device_info d) : d_temp(NULL), d_temp_size(0)
    {
        cuda_set_device(d);
    }

    ~cub_algorithm()
    {
        if (d_temp != NULL)
            cudaFree(d_temp);
    }
};

static register_algorithms<cub_algorithm> register_cub;
