const std = @import("std");

pub const Vec3 = @Vector(3, f64);

pub const zero: Vec3 = @splat(0);

pub fn x(v: Vec3) f64 {
    return v[0];
}

pub fn y(v: Vec3) f64 {
    return v[1];
}

pub fn z(v: Vec3) f64 {
    return v[2];
}

pub fn magnitudeSquared(v: Vec3) f64 {
    return dot(v, v);
}

pub fn magnitude(v: Vec3) f64 {
    return @sqrt(magnitudeSquared(v));
}

pub fn dot(a: Vec3, b: Vec3) f64 {
    return @reduce(.Add, a * b);
}

pub fn cross(lhs: Vec3, rhs: Vec3) Vec3 {
    return .{
        lhs[1] * rhs[2] - lhs[2] * rhs[1],
        lhs[2] * rhs[0] - lhs[0] * rhs[2],
        lhs[0] * rhs[1] - lhs[1] * rhs[0],
    };
}

pub fn normalized(v: Vec3) Vec3 {
    const mag = magnitude(v);
    if (mag == 0) return zero;
    return v / @as(Vec3, @splat(mag));
}

const Formatter = std.fmt.Formatter;

pub fn fmtColor(v: Vec3) Formatter(formatColor) {
    return .{ .data = v };
}

pub fn formatColor(
    v: Vec3,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    const r: u8 = @intFromFloat(255.999 * v[0]);
    const g: u8 = @intFromFloat(255.999 * v[1]);
    const b: u8 = @intFromFloat(255.999 * v[2]);
    return writer.print("{d} {d} {d}", .{ r, g, b });
}
