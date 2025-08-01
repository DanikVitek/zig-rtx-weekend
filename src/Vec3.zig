const std = @import("std");
const Random = std.Random;

v: Repr,

pub const Repr = @Vector(3, f64);

const Self = @This();

pub const zero: Self = .splat(0);
pub const x_axis: Self = .init(.{ 1, 0, 0 });
pub const y_axis: Self = .init(.{ 0, 1, 0 });
pub const z_axis: Self = .init(.{ 0, 0, 1 });
pub const neg_x_axis: Self = .init(.{ -1, 0, 0 });
pub const neg_y_axis: Self = .init(.{ 0, -1, 0 });
pub const neg_z_axis: Self = .init(.{ 0, 0, -1 });

pub inline fn x(self: Self) f64 {
    return self.v[0];
}

pub inline fn y(self: Self) f64 {
    return self.v[1];
}

pub inline fn z(self: Self) f64 {
    return self.v[2];
}

pub inline fn init(v: Repr) Self {
    return .{ .v = v };
}

pub inline fn splat(scalar: f64) Self {
    return .{ .v = @splat(scalar) };
}

pub inline fn neg(self: Self) Self {
    return .{ .v = -self.v };
}

pub inline fn add(self: Self, other: Self) Self {
    return .{ .v = self.v + other.v };
}

pub inline fn sub(self: Self, other: Self) Self {
    return .{ .v = self.v - other.v };
}

pub inline fn mul(self: Self, other: Self) Self {
    return .{ .v = self.v * other.v };
}

pub inline fn mulScalar(self: Self, scalar: f64) Self {
    return .{ .v = self.v * @as(Repr, @splat(scalar)) };
}

pub inline fn div(self: Self, other: Self) Self {
    return .{ .v = self.v / other.v };
}

pub inline fn divScalar(self: Self, scalar: f64) Self {
    return .{ .v = self.v / @as(Repr, @splat(scalar)) };
}

pub inline fn mulAdd(a: Self, b: Self, c: Self) Self {
    return .init(@mulAdd(Repr, a.v, b.v, c.v));
}

pub inline fn mulScalarAdd(a: Self, b: f64, c: Self) Self {
    return .init(@mulAdd(Repr, a.v, @splat(b), c.v));
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

pub fn cross(lhs: Self, rhs: Self) Self {
    return .init(.{
        lhs.y() * rhs.z() - lhs.z() * rhs.y(),
        lhs.z() * rhs.x() - lhs.x() * rhs.z(),
        lhs.x() * rhs.y() - lhs.y() * rhs.x(),
    });
}

pub fn normalized(self: Self) Self {
    const mag = magnitude(self);
    if (mag == 0) return zero;
    return .init(self.v / Self.splat(mag).v);
}

pub fn randomUnit(rand: Random) Self {
    while (true) {
        const v: Self = .random(rand);
        const m2 = v.magnitude2();
        if (std.math.floatEpsAt(f64, 0) < m2 and m2 <= 1)
            return v.divScalar(@sqrt(m2));
    }
}

pub fn randomUnitInHemisphere(normal: Self, rand: Random) Self {
    const v = randomUnit(rand);
    return if (v.dot(normal) > 0)
        v
    else
        v.neg();
}

pub fn random(rand: Random) Self {
    return .{ .v = .{
        rand.float(f64) * 2 - 1,
        rand.float(f64) * 2 - 1,
        rand.float(f64) * 2 - 1,
    } };
}

pub fn isNearZero(self: Self) bool {
    const eps = 1e-8;
    return @reduce(.And, @abs(self.v) < splat(eps).v);
}

pub fn reflect(self: Self, norm: Self) Self {
    return self.sub(norm.mulScalar(2 * self.dot(norm)));
}

pub fn refract(self: Self, rand: Random, norm: Self, refraction_idx: f64) Self {
    std.debug.assert(std.math.approxEqAbs(f64, self.magnitude2(), 1, 1e-8));

    const cos_theta = @min(self.neg().dot(norm), 1);
    const sin_theta = @sqrt(1 - cos_theta * cos_theta);

    const cannot_refract: bool = refraction_idx * sin_theta > 1;
    if (cannot_refract or reflectance(cos_theta, refraction_idx) > rand.float(f64))
        return self.reflect(norm);

    const r_out_perp = norm.mulScalarAdd(cos_theta, self).mulScalar(refraction_idx);
    const r_out_parallel = norm.mulScalar(-@sqrt(@abs(1 - r_out_perp.magnitude2())));
    return r_out_perp.add(r_out_parallel);
}

fn reflectance(cos_theta: f64, refraction_idx: f64) f64 {
    const r0 = (1 - refraction_idx) / (1 + refraction_idx);
    const r02 = r0 * r0;
    return r02 + (1 - r02) * std.math.pow(f64, 1 - cos_theta, 5);
}

pub fn format(
    self: Self,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    return writer.print("({d}, {d}, {d})", .{ self.x(), self.y(), self.z() });
}

const Formatter = std.fmt.Formatter;

pub fn fmtPpmColor(v: Self) Formatter(formatPpmColor) {
    return .{ .data = v };
}

pub fn formatPpmColor(
    v: Self,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    const r: u8 = @intFromFloat(255.999 * v.x());
    const g: u8 = @intFromFloat(255.999 * v.y());
    const b: u8 = @intFromFloat(255.999 * v.z());
    return writer.print("{d} {d} {d}\n", .{ r, g, b });
}
