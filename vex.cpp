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

#define CL_USE_DEPRECATED_OPENCL_1_1_APIS
#include <CL/cl.h>
#undef CL_VERSION_1_2
#include <vexcl/vexcl.hpp>
#include <vexcl/external/clogs.hpp>
#include <stdexcept>
#include "algorithms.h"
#include "register.h"
#include "clutils.h"

class vex_algorithm
{
private:
    vex::Context ctx;

public:
    template<typename T>
    struct types
    {
        typedef vex::vector<T> vector;
        typedef vex::vector<T> scan_vector;
        typedef vex::vector<T> sort_vector;
    };

    template<typename T>
    void create(vex::vector<T> &out, std::size_t elements)
    {
        out = vex::vector<T>(ctx, elements); // uses move assignment
    }

    template<typename T>
    static void copy(const std::vector<T> &src, vex::vector<T> &dst)
    {
        vex::copy(src, dst);
    }

    template<typename T>
    static void copy(const vex::vector<T> &src, vex::vector<T> &dst)
    {
        dst = src;
    }

    template<typename T>
    static void copy(const vex::vector<T> &src, std::vector<T> &dst)
    {
        vex::copy(src, dst);
    }

    template<typename T>
    static void pre_scan(const vex::vector<T> &src, vex::vector<T> &dst) {}

    template<typename T>
    static void scan(const vex::vector<T> &src, vex::vector<T> &dst)
    {
        vex::exclusive_scan(src, dst);
    }

    template<typename K, typename V>
    static void pre_sort_by_key(vex::vector<K> &keys, vex::vector<V> &values) {}

    template<typename K, typename V>
    static void sort_by_key(vex::vector<K> &keys, vex::vector<V> &values)
    {
        vex::sort_by_key(keys, values);
    }

    template<typename T>
    static void pre_sort(vex::vector<T> &keys) {}

    template<typename T>
    static void sort(vex::vector<T> &keys)
    {
        vex::sort(keys);
    }

    void finish()
    {
        ctx.finish();
    }

    static std::string api() { return "vex"; }

    explicit vex_algorithm(device_info d) : ctx(vex::Filter::Type(type_to_cl_type(d.type)) && vex::Filter::Position(d.index))
    {
        if (!ctx)
            throw device_not_supported();
    }
};

static register_algorithms<vex_algorithm> register_vex;
