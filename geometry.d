#!/usr/bin/env rdmd-dev-module

/**
   Special thanks to:
   $(UL
   $(LI Tomasz Stachowiak (h3r3tic): allowed me to use parts of $(LINK2 https://bitbucket.org/h3r3tic/boxen/src/default/src/xf/omg, omg).)
   $(LI Jakob Øvrum (jA_cOp): improved the code a lot!)
   $(LI Florian Boesch (___doc__): helps me to understand opengl/complex maths better, see: $(LINK http://codeflow.org/).)
   $(LI #D on freenode: answered general questions about D.)
   )
   Authors: David Herberth
   License: MIT

   Note: All methods marked with pure are weakly pure since, they all access an instance member.
   All static methods are strongly pure.
*/

/* TODO: Optimize using core.simd or std.simd
   TODO: Merge with analyticgeometry
   TODO: Integrate with http://code.dlang.org/packages/blazed2
   TODO: logln, log.warn, log.error, log.info, log.debug
   TODO: Make use of staticReduce etc when they become available in Phobos.
   TODO: Go through all usages of real and use CommonType!(real, E) to make it work when E is a bignum.
   TODO: ead and perhaps make use of http://stackoverflow.com/questions/3098242/fast-vector-struct-that-allows-i-and-xyz-operations-in-d?rq=1
   TODO: Tag member functions in t_geom.d as pure as is done https://github.com/D-Programming-Language/phobos/blob/master/std/bigint.d
   TODO: Why is it preferred make slicing with [] explicit as in
   - all!"a"(vec2b(true)[])
   when accessing a data structure as a range.
   Question: When should a function return const bool instead of just bool in for instance opEquals()?

   See: https://www.google.se/search?q=point+plus+vector
   See: http://mosra.cz/blog/article.php?a=22-introducing-magnum-a-multiplatform-2d-3d-graphics-engine
*/

module geometry;

// version = unittestAllInstances;

version(NoReciprocalMul) {
    private enum rmul = false;
} else {
    private enum rmul = true;
}

import core.simd;
import std.stdio: writeln;
import std.math: sqrt, isNaN, isInfinity;
import std.conv: to;
import std.traits: isSomeString, isFloatingPoint, isNumeric, isSigned, isStaticArray, isDynamicArray, isImplicitlyConvertible, isAssignable, isArray, CommonType;
import std.string: format, rightJustify;
import std.array: join;
import std.typecons: TypeTuple;
import std.algorithm;

import mathml;
import assert_ex;
alias writeln wrln;
import dbg;
import rational: Rational;
import algorithm_ex: siota, clamp;

// TODO: Propose to add these to Phobos?

/** See also: http://forum.dlang.org/thread/bug-6384-3@http.d.puremagic.com/issues/
    See also: http://forum.dlang.org/thread/jrqiiicmtpenzokfxvlz@forum.dlang.org */
template isOpBinary(T, string op, U) { enum isOpBinary = is(typeof(mixin("T.init" ~ op ~ "U.init"))); }

template isComparable(T) { enum bool isComparable = is(typeof({ return T.init <  T.init; })); }
template isEquable   (T) { enum bool isEquable    = is(typeof({ return T.init == T.init; })); }
template isNotEquable(T) { enum bool isNotEquable = is(typeof({ return T.init != T.init; })); }
version (unittest) {
    static assert(isComparable!int);
    static assert(isComparable!string);
    static assert(!isComparable!creal);
    static struct Foo {}
    static assert(!isComparable!Foo);
    static struct Bar { bool opCmp(Bar) { return true; } }
    static assert(isComparable!Bar);
}

template isComparable(T, U) { enum bool isComparable = is(typeof({ return T.init <  U.init; })); }
template isEquable   (T, U) { enum bool isEquable    = is(typeof({ return T.init == U.init; })); }
template isNotEquable(T, U) { enum bool isNotEquable = is(typeof({ return T.init != U.init; })); }

template isVector(E)     { enum isVector     = is(typeof(isVectorImpl(E.init))); }
template isPoint(E)      { enum isPoint      = is(typeof(isPointImpl(E.init))); }
template isMatrix(E)     { enum isMatrix     = is(typeof(isMatrixImpl(E.init))); }
template isQuaternion(E) { enum isQuaternion = is(typeof(isQuaternionImpl(E.init))); }
template isPlane(E)      { enum isPlane      = is(typeof(isPlaneImpl(E.init))); }

private void isVectorImpl    (E, uint D)        (Vector    !(E, D)    vec) {}
private void isPointImpl     (E, uint D)        (Point     !(E, D)    vec) {}
private void isMatrixImpl    (E, uint R, uint C)(Matrix    !(E, R, C) mat) {}
private void isQuaternionImpl(E)                (Quaternion!(E)        qu) {}
private void isPlaneImpl     (E)                (PlaneT    !(E)         p) {}

template isFixVector(E) { enum isFixVector = isFix(typeof(isFixVectorImpl(E.init))); }
template isFixPoint(E)  { enum isFixPoint  = isFix(typeof(isFixPointImpl (E.init))); }
template isFixMatrix(E) { enum isFixMatrix = isFix(typeof(isFixMatrixImpl(E.init))); }

private void isFixVectorImpl (E, uint D)        (Vector!(E, D)    vec) {}
private void isFixPointImpl  (E, uint D)        (Point !(E, D)    vec) {}
private void isFixMatrixImpl (E, uint R, uint C)(Matrix!(E, R, C) mat) {}

// ==============================================================================================

version(unittestAllInstances) {
    enum defaultElementTypes = ["float", "double", "real"];
} else {
    enum defaultElementTypes = ["real"];
}

// See also: http://stackoverflow.com/questions/18552454/using-ctfe-to-generate-set-of-struct-aliases/18553026?noredirect=1#18553026
string makeInstanceAliases(string templateName,
                           string aliasName = "",
                           const uint minDimension = 2,
                           const uint maxDimension = 4,
                           const string[] elementTypes = defaultElementTypes)
in {
    assert(templateName.length);
    assert(minDimension <= maxDimension);
} body {
    import std.string;
    import std.conv;
    string code;
    if (!aliasName.length) {
        aliasName = templateName.toLower;
    }
    foreach (n; minDimension .. maxDimension + 1) {
        foreach (et; elementTypes) { // for each elementtype
            immutable prefix = ("alias " ~ templateName ~ "!("~et~", " ~
                                to!string(n) ~ ") " ~ aliasName ~ "" ~
                                to!string(n));
            if (et == "float") {
                code ~= (prefix ~ ";\n"); // GLSL-style prefix-less single precision
            }
            code ~= (prefix ~ et[0] ~ ";\n");
        }
    }
    return code;
}

// ==============================================================================================

/// D-Dimensional Point with Coordinate Type (Precision) E.
struct Point (E, uint D) if (D >= 1) {
    private E[D] _point;             /// Element data.
    static const uint dimension = D; /// Get dimensionality.

    @property @trusted string toString() { return format("point:%s", _point); }

    @safe pure nothrow:

    /** Returns: Area 0 */
    @property auto area() const { return 0; }

    auto opSlice() { return _point[]; }
}
mixin(makeInstanceAliases("Point"));

enum Orient { column, row }; // Vector Orientation.

/// D-Dimensional Vector with Coordinate/Element Type (Precision) E.
/// See also: http://physics.stackexchange.com/questions/16850/is-0-0-0-an-undefined-vector
struct Vector(E, uint D,
              bool normalizedFlag = false, // set to true for UnitVectors
              Orient orient = Orient.column) if (D >= 1) {

    // Construct from vector.
    this(V)(V vec) if (isVector!V &&
                       // TOREVIEW: is(T.E : E) &&
                       (V.dimension >= dimension)) {
        foreach (i; siota!(0, D)) {
            _vector[i] = vec._vector[i];
        }
    }

    /** Construct from Scalar $(D VALUE). */
    this(S)(S scalar) if (isAssignable!(E, S)) { clear(scalar); } // ToReview:

    /** Construct from combination of arguments. */
    this(Args...)(Args args) { construct!(0)(args); }

    static const uint dimension = D; /// Get dimensionality.

    @property @safe pure nothrow string toOrientationString() const { return orient == Orient.column ? "Column" : "Row"; }
    @property @safe pure nothrow string joinString() const { return orient == Orient.column ? " \\\\ " : " & "; }
    @property @trusted string toString() const { return toOrientationString ~ "Vector:" ~ to!string(_vector); }
    /** Returns: LaTeX Encoding of Vector. http://www.thestudentroom.co.uk/wiki/LaTex#Matrices_and_Vectors */
    @property @trusted string toLaTeX() const { return "\\begin{pmatrix} " ~ map!(to!string)(_vector[]).join(joinString) ~ " \\end{pmatrix}" ; }
    @property @trusted string toMathML() const {
        // opening
        string str = "<mrow>
  <mo>(</mo>
  <mtable>";

        if (orient == Orient.row) {
            str ~=  "
    <mtr>";
        }

        foreach (i; siota!(0, D)) {
            final switch (orient) {
            case Orient.column:
                str ~= "
    <mtr>
      <mtd>
        <mn>" ~ to!string(_vector[i]) ~ "</mn>
      </mtd>
    </mtr>";
                break;
            case Orient.row:
                str ~= "
      <mtd>
        <mn>" ~ to!string(_vector[i]) ~ "</mn>
      </mtd>";
                break;
            }
        }

        if (orient == Orient.row) {
            str ~=  "
    </mtr>";
        }

        // closing
        str ~= "
  </mtable>
  <mo>)</mo>
</mrow>
";
        return str;
    }

    @safe pure nothrow:

    /// Returns: true if all values are not nan and finite, otherwise false.
    @property bool ok() const {
        foreach (v; _vector) {
            if (isNaN(v) || isInfinity(v)) {
                return false;
            }
        }
        return true;
    }
    // NOTE: Disabled this because I want same behaviour as MATLAB: bool opCast(T : bool)() const { return ok; }
    bool opCast(T : bool)() const { return all!"a" (_vector[]) ; }

    /// Returns: Pointer to the coordinates.
    @property auto value_ptr() { return _vector.ptr; }

    /// Sets all values to $(D value).
    void clear(E value) { foreach (i; siota!(0, D)) { _vector[i] = value; } }

    /** Returns: Whole Internal Array of E. */
    auto opSlice() { return _vector[]; }
    /** Returns: Slice of Internal Array of E. */
    auto opSlice(uint off, uint len) { return _vector[off..len]; }
    /** Returns: Reference to Internal Vector Element. */
    ref inout(E) opIndex(uint i) inout { return _vector[i]; }

    bool opEquals(S)(const S scalar) const if (isAssignable!(E, S)) { // TOREVIEW: Use isNotEquable instead
        foreach (i; siota!(0, D)) {
            if (_vector[i] != scalar) {
                return false;
            }
        }
        return true;
    }
    bool opEquals(F)(const F vec) const if (isVector!F && dimension == F.dimension) { // TOREVIEW: Use isEquable instead?
        return _vector == vec._vector;
    }
    bool opEquals(F)(const(F)[] array) const if (isAssignable!(E, F) && !isArray!F && !isVector!F) { // TOREVIEW: Use isNotEquable instead?
        if (array.length != dimension) {
            return false;
        }
        foreach (i; siota!(0, D)) {
            if (_vector[i] != array[i]) {
                return false;
            }
        }
        return true;
    }

    static void isCompatibleVectorImpl(uint d)(Vector!(E, d) vec) if (d <= dimension) {}
    static void isCompatibleMatrixImpl(uint r, uint c)(Matrix!(E, r, c) m) {}
    template isCompatibleVector(T) { enum isCompatibleVector = is(typeof(isCompatibleVectorImpl(T.init))); }
    template isCompatibleMatrix(T) { enum isCompatibleMatrix = is(typeof(isCompatibleMatrixImpl(T.init))); }

    private void construct(uint i)() {
        static assert(i == D, "Not enough arguments passed to constructor"); }
    private void construct(uint i, T, Tail...)(T head, Tail tail) {
        static        if (i >= D) {
            static assert(false, "Too many arguments passed to constructor");
        } else static if (is(T : E)) {
            _vector[i] = head;
            construct!(i + 1)(tail);
        } else static if (isDynamicArray!T) {
            static assert((Tail.length == 0) && (i == 0), "Dynamic array can not be passed together with other arguments");
            _vector[] = head[];
        } else static if (isStaticArray!T) {
            _vector[i .. i + T.length] = head[];
            construct!(i + T.length)(tail);
        } else static if (isCompatibleVector!T) {
            _vector[i .. i + T.dimension] = head._vector[];
            construct!(i + T.dimension)(tail);
        } else {
            static assert(false, "Vector constructor argument must be of type " ~ E.stringof ~ " or Vector, not " ~ T.stringof);
        }
    }

    // private void dispatchImpl(int i, string s, int size)(ref E[size] result) const {
    //     static if (s.length > 0) {
    //         result[i] = _vector[coordToIndex!(s[0])];
    //         dispatchImpl!(i + 1, s[1..$])(result);
    //     }
    // }

    // /// Implements dynamic swizzling.
    // /// Returns: a Vector
    // @property Vector!(E, s.length) opDispatch(string s)() const {
    //     E[s.length] ret;
    //     dispatchImpl!(0, s)(ret);
    //     Vector!(E, s.length) ret_vec;
    //     ret_vec._vector = ret;
    //     return ret_vec;
    // }

    ref inout(Vector) opUnary(string op : "+")() inout { return this; }

    Vector   opUnary(string op : "-")() const if (isSigned!(E)) {
        Vector y;
        foreach (i; siota!(0, D)) {
            y._vector[i] = - _vector[i];
        }
        return y;
    }

    auto opBinary(string op, F)(Vector!(F, D) r) const if ((op == "+") ||
                                                           (op == "-")) {
        Vector!(CommonType!(E, F), D) y;
        foreach (i; siota!(0, D)) {
            y._vector[i] = mixin("_vector[i]" ~ op ~ "r._vector[i]");
        }
        return y;
    }

    Vector opBinary(string op : "*", F)(F r) const {
        Vector!(CommonType!(E, F), D) y;
        foreach (i; siota!(0, dimension)) {
            y._vector[i] = _vector[i] * r;
        }
        return y;
    }

    Vector!(CommonType!(E, F), D) opBinary(string op : "*", F)(Vector!(F, D) r) const {
        // MATLAB-style Product Behaviour
        static if (orient == Orient.column &&
                   r.orient == Orient.row) {
            return outer(this, r);
        } else static if (orient == Orient.row &&
                          r.orient == Orient.column) {
            return dot(this, r);
        } else {
            static assert(false, "Incompatible vector dimensions.");
        }
    }

    /** Multiply this Vector with Matrix. */
    Vector!(E, T.rows) opBinary(string op : "*", T)(T inp) const if (isCompatibleMatrix!T && (T.cols == dimension)) {
        Vector!(E, T.rows) ret;
        ret.clear(0);
        foreach (c; siota!(0, T.cols)) {
            foreach (r; siota!(0, T.rows)) {
                ret._vector[r] += _vector[c] * inp.at(r,c);
            }
        }
        return ret;
    }

    /** Multiply this Vector with Matrix. */
    auto opBinaryRight(string op, T)(T inp) const if (!isVector!T && !isMatrix!T && !isQuaternion!T) {
        return this.opBinary!(op)(inp);
    }

    /** TODO: Suitable Restrictions on F. */
    void opOpAssign(string op, F)(F r) /* if ((op == "+") || (op == "-") || (op == "*") || (op == "%") || (op == "/") || (op == "^^")) */ {
        foreach (i; siota!(0, dimension)) {
            mixin("_vector[i]" ~ op ~ "= r;");
        }
    }
    unittest {
        auto v2 = vec2(1, 3);
        v2 *= 5.0f; assert(v2[] == [5, 15]);
        v2 ^^= 2; assert(v2[] == [25, 225]);
        v2 /= 5; assert(v2[] == [5, 45]);
    }

    void opOpAssign(string op)(Vector r) if ((op == "+") || (op == "-")) {
        foreach (i; siota!(0, dimension)) {
            mixin("_vector[i]" ~ op ~ "= r._vector[i];");
        }
    }

    /// Returns: Non-Rooted $(D N) - Norm of $(D x).
    @safe pure nothrow auto nrnNorm(uint N)() const if (isNumeric!E && N >= 1) {
        static if (isFloatingPoint!E) {
            real y = 0;                 // TOREVIEW: Use maximum precision for now
        } else {
            E y = 0;                // TOREVIEW: Use other precision for now
        }
        foreach (i; siota!(0, D)) { y += _vector[i] ^^ N; }
        return y;
    }

    /// Returns: Squared Magnitude of x.
    @property @safe pure nothrow real magnitudeSquared()() const if (isNumeric!E) {
        static if (normalizedFlag) {
            return 1;
        } else {
            return nrnNorm!2;
        }
    }
    /// Returns: Magnitude of x.
    @property @safe pure nothrow real magnitude()() const if (isNumeric!E) {
        static if (normalizedFlag) {
            return 1;
        } else {
            return sqrt(magnitudeSquared);
        }
    }

    static if (isFloatingPoint!(E)) {

        /// Normalize $(D this).
        void normalize() {
            if (this != 0) {         // zero vector have zero magnitude
                immutable m = this.magnitude;
                foreach (i; siota!(0, D)) {
                    _vector[i] /= m;
                }
            }
        }

        /// Returns: normalizedFlag Copy of this Vector.
        @property pure Vector normalized() const {
            Vector y = this;
            y.normalize();
            return y;
        }
        unittest {
            static if (D == 2) {
                assert(Vector(3, 4).magnitude == 5);
            }
            assert(Vector(0).normalized == 0);
        }
    }

    /// Returns: Vector Index at Character Coordinate $(D coord).
    private @property ref inout(E) get_(char coord)() inout {
        return _vector[coordToIndex!coord];
    }

    /// Coordinate Character c to Index
    template coordToIndex(char c) {
        static if ((c == 'x')) {
            enum coordToIndex = 0;
        } else static if ((c == 'y')) {
            enum coordToIndex = 1;
        } else static if ((c == 'z')) {
            static assert(D >= 3, "The " ~ c ~ " property is only available on vectors with a third dimension.");
            enum coordToIndex = 2;
        } else static if ((c == 'w')) {
            static assert(D >= 4, "The " ~ c ~ " property is only available on vectors with a fourth dimension.");
            enum coordToIndex = 3;
        } else {
            static assert(false, "Accepted coordinates are x, s, r, u, y, g, t, v, z, p, b, w, q and a not " ~ c ~ ".");
        }
    }

    /// Updates the vector with the values from other.
    void update(Vector!(E, D) other) { _vector = other._vector; }

    static if (D == 2) { void set(E x, E y) { _vector[0] = x; _vector[1] = y; } }
    else static if (D == 3) { void set(E x, E y, E z) { _vector[0] = x; _vector[1] = y; _vector[2] = z; } }
    else static if (D == 4) { void set(E x, E y, E z, E w) { _vector[0] = x; _vector[1] = y; _vector[2] = z; _vector[3] = w; } }

    static if (D >= 1) { alias get_!'x' x; }
    static if (D >= 2) { alias get_!'y' y; }
    static if (D >= 3) { alias get_!'z' z; }
    static if (D >= 4) { alias get_!'w' w; }

    static if (isNumeric!E) {
        /* Need these conversions when E is for instance ubyte.
           See this commit: https://github.com/Dav1dde/gl3n/commit/2504003df4f8a091e58a3d041831dc2522377f95 */
        enum E0 = 0.to!E;
        enum E1 = 1.to!E;
        static if (dimension == 2) {
            enum Vector e1 = Vector(E1, E0); /// canonical basis for Euclidian space
            enum Vector e2 = Vector(E0, E1); /// ditto
        } else static if (dimension == 3) {
            enum Vector e1 = Vector(E1, E0, E0); /// canonical basis for Euclidian space
            enum Vector e2 = Vector(E0, E1, E0); /// ditto
            enum Vector e3 = Vector(E0, E0, E1); /// ditto
        } else static if (dimension == 4) {
            enum Vector e1 = Vector(E1, E0, E0, E0); /// canonical basis for Euclidian space
            enum Vector e2 = Vector(E0, E1, E0, E0); /// ditto
            enum Vector e3 = Vector(E0, E0, E1, E0); /// ditto
            enum Vector e4 = Vector(E0, E0, E0, E1); /// ditto
        }
    }
    unittest {
        static if (isNumeric!E) {
            assert(vec2.e1[] == [1, 0]);
            assert(vec2.e2[] == [0, 1]);

            assert(vec3.e1[] == [1, 0, 0]);
            assert(vec3.e2[] == [0, 1, 0]);
            assert(vec3.e3[] == [0, 0, 1]);

            assert(vec4.e1[] == [1, 0, 0, 0]);
            assert(vec4.e2[] == [0, 1, 0, 0]);
            assert(vec4.e3[] == [0, 0, 1, 0]);
            assert(vec4.e4[] == [0, 0, 0, 1]);
        }
    }

    /**  */
    private E[D] _vector;            /// Element data.

    unittest {
        // static if (isSigned!(E)) { assert(-Vector!(E,D)(+2),
        //                                   +Vector!(E,D)(-2)); }
    }
}
mixin(makeInstanceAliases("Vector", "vec", 2,4, ["ubyte", "int", "float", "double", "real", "bool"]));

unittest {
    assert(vec2f(2, 3)[] == [2, 3]);
    assert(vec2f(2, 3)[0] == 2);
    assert(vec2f(2) == 2);
    assert(vec2f(true) == true);
    assert(vec2b(true) == true);
    assert(all!"a"(vec2b(true)[]));
    assert(any!"a"(vec2b(false, true)[]));
    assert(any!"a"(vec2b(true, false)[]));
    assert(!any!"a"(vec2b(false, false)[]));
    wrln(vec2f(2, 3));
    wrln(transpose(vec2f(11, 22)));
    wrln(vec2f(11, 22).toLaTeX);
    wrln(vec2f(11, 22).T.toLaTeX);
    assert((vec2(1, 3)*2.5f)[] == [2.5f, 7.5f]);
}

@safe pure nothrow auto transpose(E, uint D, bool normalizedFlag)(in Vector!(E, D, normalizedFlag, Orient.column) a) {
    return Vector!(E, D, normalizedFlag, Orient.row)(a);
}
alias transpose T; // C++ Armadillo naming convention.

@safe pure nothrow auto elementwiseLessThanOrEqual(Ta, Tb, uint D)(Vector!(Ta, D) a,
                                                                   Vector!(Tb, D) b) {
    Vector!(bool, D) c;
    foreach (i; siota!(0, D)) {
        c[i] = a[i] <= b[i];
    }
    return c;
}
unittest {
    assert(elementwiseLessThanOrEqual(vec2f(1, 1),
                                           vec2f(2, 2)) == vec2b(true, true));
}

/// Returns: Scalar/Dot-Product of Two Vectors $(D a) and $(D b).
@safe pure nothrow T dotProduct(T, U)(in T a, in U b) if (isVector!T &&
                                                          isVector!U &&
                                                          (T.dimension ==
                                                           U.dimension)) {
    T c;
    foreach (i; siota!(0, T.dimension)) {
        c[i] = a[i] * b[i];
    }
    return c;
}
alias dotProduct dot;

/// Returns: Outer-Product of Two Vectors $(D a) and $(D b).
@safe pure nothrow auto outerProduct(Ta, Tb, uint Da, uint Db)(in Vector!(Ta, Da) a,
                                                               in Vector!(Tb, Db) b) if (Da >= 1,
                                                                                         Db >= 1) {
    Matrix!(CommonType!(Ta, Tb), Da, Db) y;
    foreach (r; siota!(0, Da)) {
        foreach (c; siota!(0, Db)) {
            y.at(r,c) = a[r] * b[c];
        }
    }
    return y;
}
alias outerProduct outer;

/// Returns: Vector/Cross-Product of two 3-Dimensional Vectors.
@safe pure nothrow T cross(T)(in T a, in T b) if (isVector!T &&
                                                  T.dimension == 3) { /// isVector!T &&
    return T(a.y * b.z - b.y * a.z,
             a.z * b.x - b.z * a.x,
             a.x * b.y - b.x * a.y);
}

/// Returns: (Euclidean) Distance between $(D a) and $(D b).
@safe pure nothrow real distance(T, U)(in T a,
                                       in U b) if ((isVector!T && // either both vectors
                                                    isVector!U) ||
                                                   (isPoint!T && // or both points
                                                    isPoint!U)) {
    return (a - b).magnitude;
}

unittest {
    auto v1 = vec3f(1, 2, -3);
    auto v2 = vec3f(1, 3, 2);
    assert(cross(v1, v2)[] == [13, -5, 1]);
    assert(distance(vec2f(0, 0),
                         vec2f(0, 10)) == 10);
    assert(distance(vec2f(0, 0),
                         vec2d(0, 10)) == 10);
    assert(dot(v1, v2) ==
                dot(v2, v1)); // commutative
}

// ==============================================================================================

enum Layout { columnMajor, rowMajor }; // Matrix Storage Major Dimension.

/// Base template for all matrix-types.
/// Params:
///  type = all values get stored as this type
///  rows_ = rows of the matrix
///  cols_ = columns of the matrix
///  layout = matrix layout
struct Matrix(type, uint rows_, uint cols_, Layout layout = Layout.rowMajor) if ((rows_ >= 1) && (cols_ >= 1)) {
    alias type mT; /// Internal type of the _matrix
    static const uint rows = rows_; /// Number of rows
    static const uint cols = cols_; /// Number of columns

    /// Matrix $(RED row-major) in memory.
    static if (layout == Layout.rowMajor) {
        private mT[cols][rows] _matrix; // In C it would be mt[rows][cols], D does it like this: (mt[cols])[rows]
        @safe nothrow ref inout(mT) opCall(uint row, uint col) inout { return _matrix[row][col]; }
        @safe nothrow ref inout(mT)     at(uint row, uint col) inout { return _matrix[row][col]; }
    } else {
        private mT[rows][cols] _matrix; // In C it would be mt[cols][rows], D does it like this: (mt[rows])[cols]
        @safe nothrow ref inout(mT) opCall(uint row, uint col) inout { return _matrix[col][row]; }
        @safe nothrow ref inout(mT) at    (uint row, uint col) inout { return _matrix[col][row]; }
    }
    alias _matrix this;


    /// Returns: The pointer to the stored values as OpenGL requires it.
    /// Note this will return a pointer to a $(RED row-major) _matrix,
    /// $(RED this means you've to set the transpose argument to GL_TRUE when passing it to OpenGL).
    /// Examples:
    /// ---
    /// // 3rd argument = GL_TRUE
    /// glUniformMatrix4fv(programs.main.model, 1, GL_TRUE, mat4.translation(-0.5f, -0.5f, 1.0f).value_ptr);
    /// ---
    @property auto value_ptr() { return _matrix[0].ptr; }

    /// Returns: The current _matrix formatted as flat string.
    @property @trusted string toString() { return format("%s", _matrix); }
    @property @trusted string toLaTeX() const {
        string s;
        foreach (r; siota!(0, rows)) {
            foreach (c; siota!(0, cols)) {
                s ~= to!string(at(r, c)) ;
                if (c != cols - 1) { s ~= " & "; } // if not last column
            }
            if (r != rows - 1) { s ~= " \\\\ "; } // if not last row
        }
        return "\\begin{pmatrix} " ~ s ~ " \\end{pmatrix}" ;
    }
    @property @trusted string toMathML() const {
        // opening
        string str = "<mrow>
  <mo>(</mo>
  <mtable>";

        foreach (r; siota!(0, rows)) {
            str ~=  "
    <mtr>";
            foreach (c; siota!(0, cols)) {
                str ~= "
      <mtd>
        <mn>" ~ to!string(at(r, c)) ~ "</mn>
      </mtd>";
            }
            str ~=  "
    </mtr>";
        }

        // closing
        str ~= "
  </mtable>
  <mo>)</mo>
</mrow>
";
        return str;
    }

    /// Returns: The current _matrix as pretty formatted string.
    @property string asPrettyString() @trusted {
        string fmtr = "%s";

        size_t rjust = max(format(fmtr, reduce!(max)(_matrix[])).length,
                           format(fmtr, reduce!(min)(_matrix[])).length) - 1;

        string[] outer_parts;
        foreach (mT[] row; _matrix) {
            string[] inner_parts;
            foreach (mT col; row) {
                inner_parts ~= rightJustify(format(fmtr, col), rjust);
            }
            outer_parts ~= " [" ~ join(inner_parts, ", ") ~ "]";
        }

        return "[" ~ join(outer_parts, "\n")[1..$] ~ "]";
    }
    alias asPrettyString toPrettyString; /// ditto

    @safe pure nothrow:
    static void isCompatibleMatrixImpl(uint r, uint c)(Matrix!(mT, r, c) m) {
    }

    template isCompatibleMatrix(T) {
        enum isCompatibleMatrix = is(typeof(isCompatibleMatrixImpl(T.init)));
    }

    static void isCompatibleVectorImpl(uint d)(Vector!(mT, d) vec) {
    }

    template isCompatibleVector(T) {
        enum isCompatibleVector = is(typeof(isCompatibleVectorImpl(T.init)));
    }

    private void construct(uint i, T, Tail...)(T head, Tail tail) {
        static if (i >= rows*cols) {
            static assert(false, "Too many arguments passed to constructor");
        } else static if (is(T : mT)) {
            _matrix[i / cols][i % cols] = head;
            construct!(i + 1)(tail);
        } else static if (is(T == Vector!(mT, cols))) {
            static if (i % cols == 0) {
                _matrix[i / cols] = head._vector;
                construct!(i + T.dimension)(tail);
            } else {
                static assert(false, "Can't convert Vector into the matrix. Maybe it doesn't align to the columns correctly or dimension doesn't fit");
            }
        } else {
            static assert(false, "Matrix constructor argument must be of type " ~ mT.stringof ~ " or Vector, not " ~ T.stringof);
        }
    }

    private void construct(uint i)() { // terminate
        static assert(i == rows*cols, "Not enough arguments passed to constructor");
    }

    /// Constructs the matrix:
    /// If a single value is passed, the matrix will be cleared with this value (each column in each row will contain this value).
    /// If a matrix with more rows and columns is passed, the matrix will be the upper left nxm matrix.
    /// If a matrix with less rows and columns is passed, the passed matrix will be stored in the upper left of an identity matrix.
    /// It's also allowed to pass vectors and scalars at a time, but the vectors dimension must match the number of columns and align correctly.
    /// Examples:
    /// ---
    /// mat2 m2 = mat2(0.0f); // mat2 m2 = mat2(0.0f, 0.0f, 0.0f, 0.0f);
    /// mat3 m3 = mat3(m2); // mat3 m3 = mat3(0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f);
    /// mat3 m3_2 = mat3(vec3(1.0f, 2.0f, 3.0f), 4.0f, 5.0f, 6.0f, vec3(7.0f, 8.0f, 9.0f));
    /// mat4 m4 = mat4.identity; // just an identity matrix
    /// mat3 m3_3 = mat3(m4); // mat3 m3_3 = mat3.identity
    /// ---
    this(Args...)(Args args) {
        construct!(0)(args);
    }

    this(T)(T mat) if (isMatrix!T && (T.cols >= cols) && (T.rows >= rows)) {
        _matrix[] = mat._matrix[];
    }

    this(T)(T mat) if (isMatrix!T && (T.cols < cols) && (T.rows < rows)) {
        makeIdentity();
        foreach (r; siota!(0, T.rows)) {
            foreach (c; siota!(0, T.cols)) {
                at(r, c) = mat.at(r, c);
            }
        }
    }

    this()(mT value) { clear(value); }

    /// Returns true if all values are not nan and finite, otherwise false.
    @property bool ok() const {
        foreach (row; _matrix) {
            foreach (col; row) {
                if (isNaN(col) || isInfinity(col)) {
                    return false;
                }
            }
        }
        return true;
    }

    /// Sets all values of the matrix to value (each column in each row will contain this value).
    void clear(mT value) {
        foreach (r; siota!(0, rows)) {
            foreach (c; siota!(0, cols)) {
                at(r,c) = value;
            }
        }
    }

    static if (rows == cols) {

        /// Makes the current matrix an identity matrix.
        void makeIdentity() {
            clear(0);
            foreach (r; siota!(0, rows)) {
                at(r,r) = 1;
            }
        }

        /// Returns: Identity Matrix.
        static @property Matrix identity() {
            Matrix ret;
            ret.clear(0);

            foreach (r; siota!(0, rows)) {
                ret.at(r,r) = 1;
            }

            return ret;
        }

        /// Transpose Current Matrix.
        void transpose() { _matrix = transposed()._matrix; }

        unittest {
            mat2 m2 = mat2(1.0f);
            m2.transpose();
            assert(m2._matrix == mat2(1.0f)._matrix);
            m2.makeIdentity();
            assert(m2._matrix == [[1.0f, 0.0f],
                                  [0.0f, 1.0f]]);
            m2.transpose();
            assert(m2._matrix == [[1.0f, 0.0f],
                                  [0.0f, 1.0f]]);
            assert(m2._matrix == m2.identity._matrix);

            mat3 m3 = mat3(1.1f, 1.2f, 1.3f,
                           2.1f, 2.2f, 2.3f,
                           3.1f, 3.2f, 3.3f);
            m3.transpose();
            assert(m3._matrix == [[1.1f, 2.1f, 3.1f],
                                  [1.2f, 2.2f, 3.2f],
                                  [1.3f, 2.3f, 3.3f]]);

            mat4 m4 = mat4(2.0f);
            m4.transpose();
            assert(m4._matrix == mat4(2.0f)._matrix);
            m4.makeIdentity();
            assert(m4._matrix == [[1.0f, 0.0f, 0.0f, 0.0f],
                                  [0.0f, 1.0f, 0.0f, 0.0f],
                                  [0.0f, 0.0f, 1.0f, 0.0f],
                                  [0.0f, 0.0f, 0.0f, 1.0f]]);
            assert(m4._matrix == m4.identity._matrix);
        }

    }

    /// Returns a transposed copy of the matrix.
    @property Matrix!(mT, cols, rows) transposed() const {
        typeof(return) ret;
        foreach (r; siota!(0, rows)) {
            foreach (c; siota!(0, cols)) {
                ret.at(c,r) = at(r,c);
            }
        }
        return ret;
    }

}
alias Matrix!(float, 2, 2) mat2;
alias Matrix!(float, 3, 3) mat3;
alias Matrix!(float, 3, 4) mat34;
alias Matrix!(float, 4, 4) mat4;
alias Matrix!(float, 2, 2, Layout.columnMajor) mat2_cm;

unittest {
    auto m = mat2(1, 2,
                  3, 4);
    assert(m(0, 0) == 1);
    assert(m(0, 1) == 2);
    assert(m(1, 0) == 3);
    assert(m(1, 1) == 4);
}
unittest {
    auto m = mat2_cm(1, 3,
                     2, 4);
    assert(m(0, 0) == 1);
    assert(m(0, 1) == 2);
    assert(m(1, 0) == 3);
    assert(m(1, 1) == 4);
}

unittest {
    alias float E;
    immutable a = Vector!(E, 2, false, Orient.column)(1, 2);
    immutable b = Vector!(E, 3, false, Orient.column)(3, 4, 5);
    immutable c = outerProduct(a, b);
    assert(c[] == [[3, 4, 5],
                   [6, 8, 10]]);
}

// ==============================================================================================

/// D-Dimensional Particle with Coordinate Type (Precision) E.
struct Particle(E, uint D,
                bool normalizedFlag = false, // set to true for UnitVectors
    ) if (D >= 1) {
    Point!(E, D) position;          // Position.
    Vector!(E, D, normalizedFlag) velocity; ///< Velocity.
    E mass;                         // Mass.
    unittest {
        // wrln(Particle());
    }
}
mixin(makeInstanceAliases("Particle","particle", 2,4, defaultElementTypes));

// ==============================================================================================

/** D-Dimensional Axis-Aligned (Hyper) Box.
    We must use inclusive compares betweeen boxes and points in inclusion
    functions such as inside() and includes() in order for the behaviour of
    bounding boxes (especially in integer space) to work as desired.
 */
struct Box(E, uint D) if (D >= 1) {

    this(Vector!(E,D) lh) { min = lh; max = lh; }
    this(Vector!(E,D) l_,
         Vector!(E,D) h_) { min = l_; max = h_; }

    @property @trusted string toString() { return format("(l=%s, u=%s)", min, max); }

    /// Get Box Center.
    // @property Vector!(E,D) center() { return (min + max) / 2;}

    @safe nothrow:

    /// Constructs a Box enclosing $(D points).
    pure static Box fromPoints(in Vector!(E,D)[] points) {
        Box y;
        foreach (p; points) {
            y.expand(p);
        }
        return y;
    }

    /// Expands the Box, so that $(I v) is part of the Box.
    auto ref expand(Vector!(E,D) v) {
        foreach (i; siota!(0, D)) {
            if (min[i] > v[i]) min[i] = v[i];
            if (max[i] < v[i]) max[i] = v[i];
        }
        return this;
    }

    /// Expands Box by another Box $(D b).
    auto ref expand(Box b) { return this.expand(b.min).expand(b.max); }

    unittest {
        immutable auto b = Box(Vector!(E,D)(1),
                               Vector!(E,D)(3));
        assert(b.sides == Vector!(E,D)(2));
        immutable auto c = Box(Vector!(E,D)(0),
                               Vector!(E,D)(4));
        assert(c.sides == Vector!(E,D)(4));
        assert(c.sidesProduct == 4^^D);
        assert(unite(b, c) == c);
    }

    /** Returns: Length of Sides */
    @property auto sides() const pure { return max - min; }

    /** Returns: Area */
    @property auto sidesProduct() const pure {
        real y = 1;
        foreach (side; this.sides) {
            y *= side;
        }
        return y;
    }
    static      if (D == 2) { alias sidesProduct area;  }
    else static if (D == 3) { alias sidesProduct volume;  }
    else static if (D >= 4) { alias sidesProduct hyperVolume;  }

    alias expand include;

    Vector!(E,D) min;           /// Low.
    Vector!(E,D) max;           /// High.

    /** Either an element in min or max is nan or min <= max. */
    invariant() {
        // assert(any!"a==a.nan"(min),
        //                  all!"a || a == a.nan"(elementwiseLessThanOrEqual(min, max)[]));
    }
}
mixin(makeInstanceAliases("Box","box", 2,4, ["int", "float", "double", "real"]));

@safe pure nothrow Box!(E,D) unite(E, uint D)(Box!(E,D) a,
                                              Box!(E,D) b) { return a.expand(b); }
@safe pure nothrow Box!(E,D) unite(E, uint D)(Box!(E,D) a,
                                              Vector!(E,D) b) { return a.expand(b); }

// ==============================================================================================

/** D-Dimensional Infinite (Hyper)-Plane.
    See also: http://stackoverflow.com/questions/18600328/preferred-representation-of-a-3d-plane-in-c-c
 */
struct Plane(E, uint D) if (isFloatingPoint!E && D >= 2) {
    static const uint dimension = D; /// Get dimensionality.

    alias Vector!(E, D, true) N; /// Plane Normal Type.
    N normal;                    /// Plane Normal.
    E distance;                  /// Plane Constant (Offset from origo).

    @safe pure nothrow:

    /// Constructs the plane, from either four scalars of type $(I E)
    /// or from a 3-dimensional vector (= normal) and a scalar.
    static if (D == 2) {
        this(E a, E b, E distance) {
            this.normal.x = a;
            this.normal.y = b;
            this.distance = distance;
        }
    }
    static if (D == 3) {
        this(E a, E b, E c, E distance) {
            this.normal.x = a;
            this.normal.y = b;
            this.normal.z = c;
            this.distance = distance;
        }
    }

    this(N normal, E distance) {
        this.normal = normal;
        this.distance = distance;
    }

    // unittest {
    //     Plane p = Plane(0.0f, 1.0f, 2.0f, 3.0f);
    //     assert(p.normal == N(0.0f, 1.0f, 2.0f));
    //     assert(p.distance == 3.0f);

    //     p.normal.x = 4.0f;
    //     assert(p.normal == N(4.0f, 1.0f, 2.0f));
    //     assert(p.x == 4.0f);
    //     assert(p.y == 1.0f);
    //     assert(p.c == 2.0f);
    //     assert(p.distance == 3.0f);
    // }

    // /// Normalizes the plane inplace.
    // void normalize() {
    //     immutable E det = cast(E)1 / normal.length;
    //     normal *= det;
    //     distance *= det;
    // }

//     /// Returns: a normalized copy of the plane.
//     @property Plane normalized() const {
//         Plane y = Plane(a, b, c, distance);
//         y.normalize();
//         return y;
//     }

//     unittest {
//         Plane p = Plane(0.0f, 1.0f, 2.0f, 3.0f);
//         Plane pn = p.normalized();
//         assert(pn.normal == N(0.0f, 1.0f, 2.0f).normalized);
//         assert(almost_equal(pn.distance, 3.0f / N(0.0f, 1.0f, 2.0f).length));
//         p.normalize();
//         assert(p == pn);
//     }

//     /// Returns: the distance from a point to the plane.
//     /// Note: the plane $(RED must) be normalized, the result can be negative.
//     E distanceTo(N point) const {
//         return dot(point, normal) + distance;
//     }


//     /// Returns: the distanceTo from a point to the plane.
//     /// Note: the plane does not have to be normalized, the result can be negative.
//     E ndistance(N point) const {
//         return (dot(point, normal) + distance) / normal.length;
//     }

//     unittest {
//         Plane p = Plane(-1.0f, 4.0f, 19.0f, -10.0f);
//         assert(almost_equal(p.ndistance(N(5.0f, -2.0f, 0.0f)), -1.182992));
//         assert(almost_equal(p.ndistance(N(5.0f, -2.0f, 0.0f)),
//                             p.normalized.distanceTo(N(5.0f, -2.0f, 0.0f))));
//     }

//     bool opEquals(Plane other) const {
//         return other.normal == normal && other.distance == distance;
//     }

}
mixin(makeInstanceAliases("Plane","plane", 3,4, defaultElementTypes));

// ==============================================================================================

unittest {
    wrln(box2f(vec2f(1, 2),
               vec2f(3, 3)));
    wrln([12, 3, 3]);

    wrln(sort(vec2f(2, 3)[]));
    wrln(vec2f(2, 3));

    wrln(vec2f(2, 3));
    wrln(vec2f(2, 3));

    wrln(vec3f(2, 3, 4));

    wrln(box2f(vec2f(1, 2),
               vec2f(3, 4)));

    wrln(vec2i(2, 3));
    wrln(vec3i(2, 3, 4));
    wrln( + vec3i(2, 3, 4));
    writeln("vec2i:\n", vec2i(2, 3).toMathML);

    auto m = mat2(1, 2, 3, 4);
    writeln("LaTeX:\n", m.toLaTeX);
    writeln("MathML:\n", m.toMathML);
}
