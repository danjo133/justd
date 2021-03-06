#!/usr/bin/env rdmd-dev

/** Integer Sorting Algorithms.
    Copyright: Per Nordlöw 2014-.
    License: $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0).
    Authors: $(WEB Per Nordlöw)
 */
module isort;

import std.range: isBidirectionalRange, ElementType;
import std.traits: isUnsigned, isSigned, isIntegral, isFloatingPoint, Unsigned, Signed;

@safe pure nothrow {

    /** Biject (Shift) Signed $(D a) "up" to Unsigned (before radix sorting). */
    Unsigned!T bijectToUnsigned(T)(T a) if (isSigned!T)
    {
        return a + (cast(Unsigned!T)1 << (8*T.sizeof - 1)); // "add up""
    }
    T bijectToUnsigned(T)(T a) if (isUnsigned!T) { return a; } ///< Identity.

    /** Biject (Shift) Unsigned  $(D a) "back down" to Signed (after radix sorting). */
    void bijectFromUnsigned(U)(U a, ref Signed!U b)
    {
        b = a - (cast(Unsigned!T)1 << (8*U.sizeof - 1)); // "add down""
    }
    void bijectFromUnsigned(U)(U a, ref U b) if (isUnsigned!U) { b = a; } ///< Identity.

    /** Map a Floating Point Number \p a Back from Radix Sorting
     * (Inverse of \c radix_flip_float()).
     * - if sign is 1 (negative), it flips the sign bit back
     * - if sign is 0 (positive), it flips all bits back
     */

    /** Map Bits of Floating Point Number \p a to Unsigned Integer that can be Radix Sorted.
     * Also finds \em sign of \p a.
     * - if it's 1 (negative float), it flips all bits.
     * - if it's 0 (positive float), it flips the sign only.
     */
    /* @safe pure nothrow uint32_t  ff(uint32_t f) { return f ^ (-(int32_t) (f >> (8*sizeof(f)-1))      | 0x80000000); } */
    /* @safe pure nothrow uint32_t iff(uint32_t f) { return f ^           (((f >> (8*sizeof(f)-1)) - 1) | 0x80000000); } */
    /* @safe pure nothrow uint64_t  ff(uint64_t f) { return f ^ (-(int64_t) (f >> (8*sizeof(f)-1))      | 0x8000000000000000LL); } */
    /* @safe pure nothrow uint64_t iff(uint64_t f) { return f ^           (((f >> (8*sizeof(f)-1)) - 1) | 0x8000000000000000LL); } */
    /* @safe pure nothrow uint32_t bijectToUnsigned(float  a)  { return ff(*(uint32_t*)(&a)); } */
    /* @safe pure nothrow uint64_t bijectToUnsigned(double a)  { return ff(*(uint64_t*)(&a)); } */
    /* void bijectFromUnsigned(uint32_t a, float&   b) { uint32_t t = iff(a); b = *(float*)(&t); } */
    /* void bijectFromUnsigned(uint64_t a, double&  b) { uint64_t t = iff(a); b = *(double*)(&t); } */

    auto bijectToUnsigned(T)(T a, bool descending = false)
    {
        const ua = bijectToUnsigned(a);
        return descending ? ua.max-ua : ua;
    }
}

/**
   Radix Sort $(D x).

   Note that $(D x) can be a $(D BidirectionalRange) aswell as $(D RandomAccessRange).

   Params:
     radixNBits = Number of bits in Radix (Digit)
 */
void radixSortImpl(R, uint radixNBits = 16)(R x,
                                            const bool descending = false,
                                            bool doInPlace = false,
                                            ElementType!R elementMin = ElementType!(R).max,
                                            ElementType!R elementMax = ElementType!(R).min) @trusted pure nothrow
    if (isBidirectionalRange!R &&
        (isIntegral!(ElementType!R) ||
         isFloatingPoint!(ElementType!R))) // if doInPlace isRandomAccessRange else isBidirectionalRange
{
    immutable n = x.length; // number of elements
    alias Elem = ElementType!R;
    enum typeof(radixNBits) elemBits = 8*Elem.sizeof; // Total Number of Bits needed to code each element
    import std.algorithm: min, max;

    // if (ip_sort(x, n)) { return; }    // small size optimizations
    import std.array: uninitializedArray;

    /* Lookup number of radix bits from sizeof ElementType.
       These give optimal performance on Intel Core i7.
    */
    static if (elemBits == 8) {
        enum radixNBits = 8;
    } else static if (elemBits == 16 ||
                      elemBits == 32 ||
                      elemBits == 64) {
        enum radixNBits = 16; // this prevents "rest" digit
    } else {
        static assert("Cannot handle ElementType " ~ Elem.stringof);
    }

    // TODO: Activate this: subtract min from all values and then const uint elemBits = is_min(a_max) ? 8*sizeof(Elem) : binlog(a_max); and add it back.
    uint nDigits = elemBits / radixNBits;         // Number of \c nDigits in radix \p radixNBits

    const nRemBits = elemBits % radixNBits; // number remaining bits to sort
    if (nRemBits) { nDigits++; }     // one more for remainding bits

    enum radix = cast(typeof(radixNBits))1 << radixNBits;    // Bin Count
    enum mask = radix-1;                              // radix bit mask

    alias U = typeof(bijectToUnsigned(x[0])); // Get Unsigned Integer Type of same precision as \tparam Elem.

    if (nDigits != 1) {         // if more than one bucket sort pass (BSP)
        doInPlace = false; // we cannot do in-place because each BSP is unstable and may ruin order from previous digit passes
    }

    static if (false/* doInPlace */) {
        // Histogram Buckets Upper-Limits/Walls for values in \p x.
        Slice!size_t bins[radix] = void; // bucket slices
        for (uint d = 0; d != nDigits; ++d) { // for each digit-index \c d (in base \c radix) starting with least significant (LSD-first)
            const uint sh = d*radixNBits;   // digit bit shift

            // TODO: Activate and verify that performance is unchanged.
            // auto uize_ = [descending, sh, mask](Elem a) { return (bijectToUnsigned(a, descending) >> sh) & mask; }; // local shorthand

            // Reset Histogram Counters
            bins[] = 0;

            // Populate Histogram \c O for current digit
            U ors  = 0;             // digits "or-sum"
            U ands = ~ors;          // digits "and-product"
            for (size_t j = 0; j != n; ++j) { // for each element index \c j in \p x
                const uint i = (bijectToUnsigned(x[j], descending) >> sh) & mask; // digit (index)
                ++bins[i].high();       // increase histogram bin counter
                ors |= i; ands &= i; // accumulate bits statistics
            }
            if ((! ors) || (! ~ands)) { // if bits in digit[d] are either all \em zero or all \em one
                continue;               // no sorting is needed for this digit
            }

            // Bin Boundaries: Accumulate Bin Counters Array
            size_t bin_max = bins[0].high();
            bins[0].low() = 0;                    // first floor is always zero
            for (size_t j = 1; j != radix; ++j) { // for each successive bin counter
                bin_max = max(bin_max, bins[j].high());
                bins[j].low()  = bins[j - 1].high(); // previous roof becomes current floor
                bins[j].high() += bins[j - 1].high(); // accumulate bin counter
            }
            // TODO: if (bin_max == 1) { std::cout << "No accumulation needed!" << std::endl; }

            /** \em Unstable In-Place (Permutate) Reorder/Sort \p x.
             * Access \p x's elements in \em reverse to \em reuse filled caches from previous forward iteration.
             * \see \c in_place_indexed_reorder
             */
            for (int r = radix - 1; r >= 0; --r) { // for each radix digit r in reverse order (cache-friendly)
                while (bins[r]) {  // as long as elements left in r:th bucket
                    const uint i0 = bins[r].pop_back(); // index to first element of permutation
                    Elem          e0 = x[i0]; // value of first/current element of permutation
                    while (true) {
                        const int rN = (bijectToUnsigned(e0, descending) >> sh) & mask; // next digit (index)
                        if (r == rN) // if permutation cycle closed (back to same digit)
                            break;
                        const ai = bins[rN].pop_back(); // array index
                        swap(x[ai], e0); // do swap
                    }
                    x[i0] = e0;         // complete cycle
                }
            }
        }

    } else {
        // Histogram Buckets Upper-Limits/Walls for values in \p x.
        size_t[radix] O; // most certainly fits in the stack (L1-cache) => Use C99 variable length array (VLA) when available
        Elem[] y = uninitializedArray!(Elem[])(n); // Non-In-Place requires temporary \p y. TODO: We could allocate these as a Variable Length Arrays (VLA) for small arrays and gain extra speed.

        for (uint d = 0; d != nDigits; ++d) { // for each digit-index \c d (in base \c radix) starting with least significant (LSD-first)
            const uint sh = d*radixNBits;   // digit bit shift

            // TODO: Activate and verify that performance is unchanged.
            // auto uize_ = [descending, sh, mask](Elem x) { return (bijectToUnsigned(x, descending) >> sh) & mask; }; // local shorthand

            // Reset Histogram Counters
            O[] = 0;

            // Populate Histogram \c O for current digit
            U ors  = 0;             // digits "or-sum"
            U ands = ~ors;          // digits "and-product"
            for (size_t j = 0; j != n; ++j) { // for each element index \c j in \p x
                const uint i = (bijectToUnsigned(x[j], descending) >> sh) & mask; // digit (index)
                ++O[i];              // increase histogram bin counter
                ors |= i; ands &= i; // accumulate bits statistics
            }
            if ((! ors) || (! ~ands)) { // if bits in digit[d] are either all \em zero or all \em one
                continue;               // no sorting is needed for this digit
            }

            // Bin Boundaries: Accumulate Bin Counters Array
            for (size_t j = 1; j != radix; ++j) { // for each successive bin counter
                O[j] += O[j - 1]; // accumulate bin counter
            }

            // Reorder. Access \p x's elements in \em reverse to \em reuse filled caches from previous forward iteration.
            // \em Stable Reorder From \p x to \c y using Normal Counting Sort (see \c counting_sort above).
            for (size_t j = n - 1; j < n; --j) { // for each element \c j in reverse order. when j wraps around j < n is no longer true
                const uint i = (bijectToUnsigned(x[j], descending) >> sh) & mask; // digit (index)
                y[--O[i]] = x[j]; // reorder into y
            }

            x[] = y[];            // put them back into $(D x)
        }
    }
}

import std.stdio: writeln;

/** Test $(D radixSortImpl) with ElementType $(D Elem) */
void test(Elem)(int n) @trusted
{
    immutable show = true;
    import random_ex: randInPlace;
    import std.algorithm: sort, min, max;
    /* immutable nMax = 3; */

    auto a = new Elem[n];

    /* if (show) writeln(a[0..min(nMax, $)]); */

    import std.datetime: StopWatch, AutoStart;
    auto sw = StopWatch();

    a[].randInPlace();
    sw.reset; sw.start(); sort(a); sw.stop;
    immutable stdTime = sw.peek.usecs;

    a[].randInPlace();
    sw.reset; sw.start(); radixSortImpl(a); sw.stop;
    immutable radixTime = sw.peek.usecs;
    if (show) writeln(Elem.stringof, " n:", n, " sort:", stdTime, "us radixSort:", radixTime, "us Speed-Up:", cast(real)stdTime / radixTime);

    import std.algorithm: isSorted;
    assert(a.isSorted);

    /* if (show) writeln(a[0..min(nMax, $)]); */
}

unittest {
    import std.typetuple: TypeTuple;
    int n = 1000_000;
    foreach (ix, T; TypeTuple!(byte, short, int, long)) {
        test!T(n); // test signed
        test!(Unsigned!T)(n); // test unsigned
    }
}
