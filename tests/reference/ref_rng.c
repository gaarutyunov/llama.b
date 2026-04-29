#include <stdio.h>
#include <stdint.h>

static uint32_t random_u32(uint64_t *state)
{
	*state ^= *state >> 12;
	*state ^= *state << 25;
	*state ^= *state >> 27;
	return (uint32_t)((*state * 0x2545F4914F6CDD1DULL) >> 32);
}

int main(void)
{
	uint64_t state = 42;
	for(int i = 0; i < 10; i++)
		printf("%u\n", random_u32(&state));
	return 0;
}
