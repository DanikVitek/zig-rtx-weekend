const std = @import("std");

v: Repr,

pub const Repr = @Vector(3, f64);
const Self = @This();

pub const red: Self = .init(.{ 1, 0, 0 });
pub const green: Self = .init(.{ 0, 1, 0 });
pub const blue: Self = .init(.{ 0, 0, 1 });
pub const white: Self = .splat(1);
pub const black: Self = .splat(0);
pub const gray: Self = .splat(0.5);

pub inline fn init(v: Repr) Self {
    return .{ .v = v };
}

pub inline fn splat(scalar: f64) Self {
    return .{ .v = @splat(scalar) };
}

pub inline fn r(self: Self) f64 {
    return self.v[0];
}

pub inline fn g(self: Self) f64 {
    return self.v[1];
}

pub inline fn b(self: Self) f64 {
    return self.v[2];
}

pub inline fn add(lhs: Self, rhs: Self) Self {
    return .{ .v = lhs.v + rhs.v };
}

pub inline fn sub(lhs: Self, rhs: Self) Self {
    return .{ .v = lhs.v - rhs.v };
}

pub inline fn mul(lhs: Self, rhs: Self) Self {
    return .{ .v = lhs.v * rhs.v };
}

pub inline fn mulAssign(self: *Self, other: Self) void {
    self.v *= other.v;
}

pub inline fn mulScalar(lhs: Self, rhs: f64) Self {
    return .{ .v = lhs.v * Self.splat(rhs).v };
}

pub inline fn mulScalarAssign(self: *Self, scalar: f64) void {
    self.v *= Self.splat(scalar).v;
}

pub inline fn div(lhs: Self, rhs: Self) Self {
    return .{ .v = lhs.v / rhs.v };
}

pub inline fn divScalar(lhs: Self, rhs: f64) Self {
    return .{ .v = lhs.v / Self.splat(rhs).v };
}

pub inline fn mulAdd(x: Self, y: Self, z: Self) Self {
    return .{ .v = @mulAdd(Repr, x.v, y.v, z.v) };
}

pub inline fn mulScalarAdd(x: Self, y: f64, z: Self) Self {
    return .{ .v = @mulAdd(Repr, x.v, @splat(y), z.v) };
}

fn linearToGamma(self: Self) Self {
    return .{ .v = @max(@sqrt(self.v), black.v) };
}

pub fn format(
    self: Self,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    const clamped: Repr = std.math.clamp(
        self.linearToGamma().v,
        @as(Repr, @splat(0)),
        @as(Repr, @splat(1)),
    );
    const remapped = std.math.lerp(
        @as(Repr, @splat(0)),
        @as(Repr, @splat(255)),
        clamped,
    );

    const bytes = @as(
        @Vector(3, u8),
        @intFromFloat(@trunc(remapped)),
    );
    return writer.writeAll(&@as([3]u8, bytes));
}
