/**
 * This module contains the options managemente code of the garbage collector.
 *
 * Copyright: Copyright (C) 2010 Leandro Lucarella <http://www.llucax.com.ar/>
 *            All rights reserved.
 *
 * License: Boost Software License - Version 1.0 - August 17th, 2003
 *
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 *
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer,
 * must be included in all copies of the Software, in whole or in part, and
 * all derivative works of the Software, unless such copies or derivative
 * works are solely in the form of machine-executable object code generated by
 * a source language processor.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 * FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 * Authors: Leandro Lucarella
 */

module rt.gc.cdgc.opts;

//debug = PRINTF;

import cstdlib = tango.stdc.stdlib;
import cstring = tango.stdc.string;
import cerrno = tango.stdc.errno;
debug (PRINTF) import tango.stdc.stdio: printf;


private:


const MAX_OPT_LEN = 256;


struct Options
{
    uint verbose = 0;
    char[MAX_OPT_LEN] log_file = "";
    char[MAX_OPT_LEN] malloc_stats_file = "";
    char[MAX_OPT_LEN] collect_stats_file = "";
    bool sentinel = false;
    bool mem_stomp = false;
    version (D_HavePointerMap)
        bool conservative = false;
    else
        bool conservative = true;
    bool fork = true;
    bool eager_alloc = true;
    bool early_collect = false;
    uint min_free = 5; // percent of the heap (0-100)
    size_t prealloc_psize = 0;
    size_t prealloc_npools = 0;
}

package Options options;


debug (PRINTF)
void print_options()
{
    int b(bool v) { return v; }
    with (options)
    printf("rt.gc.cdgc.opts: verbose=%u, log_file='%s', "
            "malloc_stats_file='%s', collect_stats_file='%s', sentinel=%d, "
            "mem_stomp=%d, conservative=%d, fork=%d, eager_alloc=%d, "
            "early_collect=%d, min_free=%u, prealloc_psize=%lu, "
            "prealloc_npools=%lu\n", verbose, log_file.ptr,
            malloc_stats_file.ptr, collect_stats_file.ptr, b(sentinel),
            b(mem_stomp), b(conservative), b(fork), b(eager_alloc),
            b(early_collect), min_free, prealloc_psize, prealloc_npools);
}


bool cstr_eq(char* s1, char* s2)
{
    return cstring.strcmp(s1, s2) == 0;
}


bool parse_bool(char* value)
{
    if (value[0] == '\0')
        return true;
    return (cstdlib.atoi(value) != 0);
}


void parse_prealloc(char* value)
{
    char* end;
    cerrno.errno = 0;
    long size = cstdlib.strtol(value, &end, 10);
    if (end == value || cerrno.errno) // error parsing
        return;
    size *= 1024 * 1024; // size is supposed to be in MiB
    long npools = 1;
    if (*end == 'x') { // number of pools specified
        char* start = end + 1;
        npools = cstdlib.strtol(start, &end, 10);
        if (*end != '\0' || end == start || cerrno.errno) // error parsing
            return;
    }
    else if (*end != '\0') { // don't accept trailing garbage
        return;
    }
    if (size > 0 && npools > 0) {
        options.prealloc_psize = size;
        options.prealloc_npools = npools;
    }
}


void parse_min_free(char* value)
{
    char* end;
    long free = cstdlib.strtol(value, &end, 10);
    if (*end != '\0' || end == value || cerrno.errno || free < 0 || free > 100)
        return;
    options.min_free = free;
}


void process_option(char* opt_name, char* opt_value)
{
    if (cstr_eq(opt_name, "verbose"))
        options.verbose = cstdlib.atoi(opt_value);
    else if (cstr_eq(opt_name, "log_file"))
        cstring.strcpy(options.log_file.ptr, opt_value);
    else if (cstr_eq(opt_name, "malloc_stats_file"))
        cstring.strcpy(options.malloc_stats_file.ptr, opt_value);
    else if (cstr_eq(opt_name, "collect_stats_file"))
        cstring.strcpy(options.collect_stats_file.ptr, opt_value);
    else if (cstr_eq(opt_name, "sentinel"))
        options.sentinel = parse_bool(opt_value);
    else if (cstr_eq(opt_name, "mem_stomp"))
        options.mem_stomp = parse_bool(opt_value);
    else if (cstr_eq(opt_name, "conservative"))
        options.conservative = parse_bool(opt_value);
    else if (cstr_eq(opt_name, "fork"))
        options.fork = parse_bool(opt_value);
    else if (cstr_eq(opt_name, "eager_alloc"))
        options.eager_alloc = parse_bool(opt_value);
    else if (cstr_eq(opt_name, "early_collect"))
        options.early_collect = parse_bool(opt_value);
    else if (cstr_eq(opt_name, "min_free"))
        parse_min_free(opt_value);
    else if (cstr_eq(opt_name, "pre_alloc"))
        parse_prealloc(opt_value);
}


package void parse(char* opts_string)
{
    char[MAX_OPT_LEN] opt_name;
    opt_name[0] = '\0';
    char[MAX_OPT_LEN] opt_value;
    opt_value[0] = '\0';
    char* curr = opt_name.ptr;
    size_t i = 0;
    if (opts_string is null) {
        debug (PRINTF) printf("rt.gc.cdgc.opts: no options overriden\n");
        return;
    }
    for (; *opts_string != '\0'; opts_string++)
    {
        char c = *opts_string;
        if (i == MAX_OPT_LEN)
        {
            if (c != ':')
                continue;
            else
                i--;
        }
        switch (*opts_string)
        {
        case ':':
            curr[i] = '\0';
            process_option(opt_name.ptr, opt_value.ptr);
            i = 0;
            opt_name[0] = '\0';
            opt_value[0] = '\0';
            curr = opt_name.ptr;
            break;
        case '=':
            opt_name[i] = '\0';
            curr = opt_value.ptr;
            i = 0;
            break;
        default:
            curr[i] = c;
            ++i;
        }
    }
    if (i == MAX_OPT_LEN)
        i--;
    curr[i] = '\0';
    process_option(opt_name.ptr, opt_value.ptr);
    debug (PRINTF) print_options();
}


unittest
{
    with (options) {
        assert (verbose == 0);
        assert (log_file[0] == '\0');
        assert (sentinel == false);
        assert (mem_stomp == false);
        assert (conservative == false);
        assert (fork == true);
        assert (eager_alloc == true);
        assert (early_collect == false);
        assert (prealloc_psize == 0);
        assert (prealloc_npools == 0);
        assert (min_free == 5);
    }
    parse("mem_stomp");
    with (options) {
        assert (verbose == 0);
        assert (log_file[0] == '\0');
        assert (sentinel == false);
        assert (mem_stomp == true);
        assert (conservative == false);
        assert (fork == true);
        assert (eager_alloc == true);
        assert (early_collect == false);
        assert (prealloc_psize == 0);
        assert (prealloc_npools == 0);
        assert (min_free == 5);
    }
    parse("mem_stomp=0:verbose=2:conservative:fork=0:eager_alloc=0");
    with (options) {
        assert (verbose == 2);
        assert (log_file[0] == '\0');
        assert (sentinel == false);
        assert (mem_stomp == false);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 0);
        assert (prealloc_npools == 0);
        assert (min_free == 5);
    }
    parse("log_file=12345 67890:verbose=1:sentinel=4:mem_stomp=1");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 0);
        assert (prealloc_npools == 0);
        assert (min_free == 5);
    }
    parse("pre_alloc:min_free=30:early_collect");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == true);
        assert (prealloc_psize == 0);
        assert (prealloc_npools == 0);
        assert (min_free == 30);
    }
    parse("pre_alloc=1:early_collect=0");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 1 * 1024 * 1024);
        assert (prealloc_npools == 1);
        assert (min_free == 30);
    }
    parse("pre_alloc=5a:min_free=101");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 1 * 1024 * 1024);
        assert (prealloc_npools == 1);
        assert (min_free == 30);
    }
    parse("pre_alloc=5x:min_free=-1");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 1 * 1024 * 1024);
        assert (prealloc_npools == 1);
        assert (min_free == 30);
    }
    parse("pre_alloc=09x010:min_free=10a");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 9 * 1024 * 1024);
        assert (prealloc_npools == 10);
        assert (min_free == 30);
    }
    parse("pre_alloc=5x2:min_free=1.0");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 5 * 1024 * 1024);
        assert (prealloc_npools == 2);
        assert (min_free == 30);
    }
    parse("pre_alloc=9x5x:min_free=-1");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 5 * 1024 * 1024);
        assert (prealloc_npools == 2);
        assert (min_free == 30);
    }
    parse("pre_alloc=9x-5:min_free=0");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 5 * 1024 * 1024);
        assert (prealloc_npools == 2);
        assert (min_free == 0);
    }
    parse("pre_alloc=0x3x0x4:min_free=100");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 5 * 1024 * 1024);
        assert (prealloc_npools == 2);
        assert (min_free == 100);
    }
    parse(null);
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 5 * 1024 * 1024);
        assert (prealloc_npools == 2);
        assert (min_free == 100);
    }
    parse("");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 5 * 1024 * 1024);
        assert (prealloc_npools == 2);
        assert (min_free == 100);
    }
    parse(":");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 5 * 1024 * 1024);
        assert (prealloc_npools == 2);
        assert (min_free == 100);
    }
    parse("::::");
    with (options) {
        assert (verbose == 1);
        assert (cstring.strcmp(log_file.ptr, "12345 67890".ptr) == 0);
        assert (sentinel == true);
        assert (mem_stomp == true);
        assert (conservative == true);
        assert (fork == false);
        assert (eager_alloc == false);
        assert (early_collect == false);
        assert (prealloc_psize == 5 * 1024 * 1024);
        assert (prealloc_npools == 2);
        assert (min_free == 100);
    }
}


// vim: set et sw=4 sts=4 :
