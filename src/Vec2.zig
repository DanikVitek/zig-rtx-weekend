const std = @import("std");
const Vec3 = @import("Vec3.zig");

v: Repr,

pub const Repr = @Vector(2, f64);

const Self = @This();

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
