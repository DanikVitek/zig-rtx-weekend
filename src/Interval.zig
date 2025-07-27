const std = @import("std");
const inf = std.math.inf(f64);

min: f64,
max: f64,

pub const Self = @This();

pub const empty: Self = .{ .min = inf, .max = -inf };
pub const universe: Self = .{ .min = -inf, .max = inf };

pub fn size(self: Self) f64 {
    return self.max - self.min;
}

pub fn contains(self: Self, val: f64) bool {
    return self.min <= val and val <= self.max;
}

pub fn surrounds(self: Self, val: f64) bool {
    return self.min < val and val < self.max;
}
