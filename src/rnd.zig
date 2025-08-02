const std = @import("std");
const Random = std.Random;

threadlocal var rand_state = Random.DefaultPrng.init(42);

pub fn random() Random {
    return rand_state.random();
}
