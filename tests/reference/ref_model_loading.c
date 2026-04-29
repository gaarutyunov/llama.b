/* Read the same checkpoint with a stand-alone C reader and print the same
 * fields as test_model_loading.b. */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(int argc, char **argv)
{
	if(argc < 2){
		fprintf(stderr, "usage: ref_model_loading <checkpoint>\n");
		return 1;
	}
	FILE *f = fopen(argv[1], "rb");
	if(f == NULL){
		fprintf(stderr, "cannot open %s\n", argv[1]);
		return 1;
	}
	int32_t cfg[7];
	if(fread(cfg, sizeof(int32_t), 7, f) != 7){
		fprintf(stderr, "short config\n");
		return 1;
	}
	int vocab_size = cfg[5];
	if(vocab_size < 0) vocab_size = -vocab_size;
	printf("dim=%d\n",        cfg[0]);
	printf("hidden_dim=%d\n", cfg[1]);
	printf("n_layers=%d\n",   cfg[2]);
	printf("n_heads=%d\n",    cfg[3]);
	printf("n_kv_heads=%d\n", cfg[4]);
	printf("vocab_size=%d\n", vocab_size);
	printf("seq_len=%d\n",    cfg[6]);
	float w[10];
	if(fread(w, sizeof(float), 10, f) != 10){
		fprintf(stderr, "short weights\n");
		return 1;
	}
	for(int i = 0; i < 10; i++)
		printf("w%d=%.6f\n", i, (double)w[i]);
	fclose(f);
	return 0;
}
