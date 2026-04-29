/* Reference rmsnorm output, matches the Limbo implementation exactly. */
#include <math.h>
#include <stdio.h>

static void rmsnorm(float *o, const float *x, const float *w, int size)
{
	float ss = 0.0f;
	for(int j = 0; j < size; j++)
		ss += x[j] * x[j];
	ss /= size;
	ss += 1e-5f;
	ss = 1.0f / sqrtf(ss);
	for(int j = 0; j < size; j++)
		o[j] = w[j] * (ss * x[j]);
}

int main(void)
{
	float x[] = {1.0f, 2.0f, 3.0f, 4.0f};
	float w[] = {0.5f, 0.5f, 0.5f, 0.5f};
	float o[4];
	rmsnorm(o, x, w, 4);
	for(int i = 0; i < 4; i++)
		printf("%.6f\n", (double)o[i]);
	return 0;
}
