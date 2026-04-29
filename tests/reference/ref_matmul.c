#include <stdio.h>

static void matmul(float *out, const float *x, const float *w, int n, int d)
{
	for(int i = 0; i < d; i++){
		float val = 0.0f;
		for(int j = 0; j < n; j++)
			val += w[i*n + j] * x[j];
		out[i] = val;
	}
}

int main(void)
{
	float w[12], x[4], o[3];
	for(int i = 0; i < 12; i++) w[i] = (float)(i + 1);
	for(int i = 0; i < 4; i++)  x[i] = (float)(i + 1);
	matmul(o, x, w, 4, 3);
	for(int i = 0; i < 3; i++)
		printf("%.6f\n", (double)o[i]);
	return 0;
}
