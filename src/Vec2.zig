const std = @import("std");
const Vec3 = @import("Vec3.zig");
const Random = std.Random;

v: Repr,

pub const Repr = @Vector(2, f64);

const Self = @This();

pub const zero: Self = .splat(0);
pub const x_axis: Self = .init(.{ 1, 0 });
pub const y_axis: Self = .init(.{ 0, 1 });
pub const neg_x_axis: Self = .init(.{ -1, 0 });
pub const neg_y_axis: Self = .init(.{ 0, -1 });

pub inline fn init(v: Repr) Self {
    return .{ .v = v };
}

pub inline fn splat(v: f64) Self {
    return .init(@splat(v));
}

pub inline fn x(self: Self) f64 {
    return self.v[0];
}

pub inline fn y(self: Self) f64 {
    return self.v[1];
}

pub inline fn xy0(self: Self) Vec3 {
    return .init(.{ self.x(), self.y(), 0 });
}

pub inline fn add(self: Self, other: Self) Self {
    return .init(self.v + other.v);
}

pub inline fn sub(self: Self, other: Self) Self {
    return .init(self.v - other.v);
}

pub inline fn mul(self: Self, other: Self) Self {
    return .init(self.v * other.v);
}

pub inline fn mulScalar(self: Self, val: f64) Self {
    return .init(self.v * splat(val).v);
}

pub inline fn div(self: Self, other: Self) Self {
    return .init(self.v / other.v);
}

pub inline fn divScalar(self: Self, val: f64) Self {
    return .init(self.v / splat(val).v);
}

pub inline fn mulAdd(a: Self, b: Self, c: Self) Self {
    return .init(@mulAdd(Repr, a.v, b.v, c.v));
}

pub inline fn mulScalarAdd(a: f64, b: Self, c: Self) Self {
    return .init(@mulAdd(Repr, @splat(a), b.v, c.v));
}

pub fn magnitude(self: Self) f64 {
    return @sqrt(self.magnitude2());
}

pub const length = magnitude;

pub fn magnitude2(self: Self) f64 {
    return dot(self, self);
}

pub const length2 = magnitude2;

pub fn dot(lhs: Self, rhs: Self) f64 {
    return @reduce(.Add, lhs.v * rhs.v);
}

pub fn normalized(self: Self) Self {
    const mag = magnitude(self);
    if (mag == 0) return zero;
    return .init(self.v / Self.splat(mag).v);
}

pub fn randomInUnitDisk(rand: Random) Self {
    while (true) {
        const v: Self = .random(rand);
        const m2 = v.magnitude2();
        if (m2 <= 1) return v.divScalar(@sqrt(m2));
    }
}

pub fn random(rand: Random) Self {
    return .{ .v = .{
        rand.float(f64) * 2 - 1,
        rand.float(f64) * 2 - 1,
    } };
}
