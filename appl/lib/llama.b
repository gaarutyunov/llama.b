implement Llama;

include "sys.m";
	sys: Sys;

include "math.m";
	math: Math;

include "llama.m";

stderr:	ref Sys->FD;
stdout:	ref Sys->FD;

# ----------------------------------------------------------------------------
# module bootstrap

init(): int
{
	sys = load Sys Sys->PATH;
	if(sys == nil)
		return -1;
	math = load Math Math->PATH;
	if(math == nil)
		return -1;
	stderr = sys->fildes(2);
	stdout = sys->fildes(1);
	return 0;
}

# ----------------------------------------------------------------------------
# byte / float helpers
#
# the karpathy checkpoint format uses little-endian IEEE-754 single
# precision floats and 32-bit signed integers.  Limbo "real" is 64-bit so
# we widen on read.

bytes_to_int(b: array of byte, off: int): int
{
	return (int b[off])
		| ((int b[off+1]) << 8)
		| ((int b[off+2]) << 16)
		| ((int b[off+3]) << 24);
}

bytes_to_real(b: array of byte, off: int): real
{
	return math->bits32real(bytes_to_int(b, off));
}

# bulk read: convert a slice of N float32 from bytes starting at off into a
# fresh array of real of length n.
read_floats(b: array of byte, off, n: int): array of real
{
	out := array[n] of real;
	for(i := 0; i < n; i++)
		out[i] = math->bits32real(bytes_to_int(b, off + i*4));
	return out;
}

# safe read: read exactly n bytes into buf at off, return success
fullread(fd: ref Sys->FD, buf: array of byte, n: int): int
{
	off := 0;
	while(off < n){
		k := sys->read(fd, buf[off:], n - off);
		if(k <= 0)
			return -1;
		off += k;
	}
	return 0;
}

# ----------------------------------------------------------------------------
# math primitives

rmsnorm(o, x, weight: array of real, size: int)
{
	ss := 0.0;
	for(j := 0; j < size; j++)
		ss += x[j] * x[j];
	ss /= real size;
	ss += 1.0e-5;
	ss = 1.0 / math->sqrt(ss);
	for(j = 0; j < size; j++)
		o[j] = weight[j] * (ss * x[j]);
}

# softmax of x[off:off+size] in place
softmax(x: array of real, off, size: int)
{
	max_val := x[off];
	for(i := 1; i < size; i++)
		if(x[off+i] > max_val)
			max_val = x[off+i];
	sum := 0.0;
	for(i = 0; i < size; i++){
		x[off+i] = math->exp(x[off+i] - max_val);
		sum += x[off+i];
	}
	for(i = 0; i < size; i++)
		x[off+i] /= sum;
}

# matrix-vector: xout (d,) = w[woff:woff+d*n] (d,n) @ x (n,)
matmul(xout, x, w: array of real, woff, n, d: int)
{
	for(i := 0; i < d; i++){
		val := 0.0;
		base := woff + i*n;
		for(j := 0; j < n; j++)
			val += w[base + j] * x[j];
		xout[i] = val;
	}
}

# ----------------------------------------------------------------------------
# rng (xorshift64*).  The C version mutates an unsigned 64-bit state in
# place; Limbo doesn't really do "ref to big", and `ref` taken on a
# primitive copies the value, so we expose a pure-functional version that
# returns the new state alongside the produced value.

random_u32(state: big): (big, int)
{
	s := state;
	s ^= u64shr(s, 12);
	s ^= s << 25;
	s ^= u64shr(s, 27);
	# multiply by 0x2545F4914F6CDD1D (mod 2^64) and take top 32 bits.
	r := s * (big 16r2545F4914F6CDD1D);
	return (s, int u64shr(r, 32));
}

# logical (unsigned) right shift on a `big`.  Limbo's `>>` is arithmetic
# on signed types; we mask off the top `n` bits to emulate the unsigned
# behaviour the xorshift algorithm needs.
u64shr(x: big, n: int): big
{
	if(n == 0)
		return x;
	mask := (big 1 << (64 - n)) - big 1;
	return (x >> n) & mask;
}

random_f32(state: big): (big, real)
{
	(ns, u) := random_u32(state);
	# treat the 32-bit value as unsigned by masking off the top half
	uu := big u & ((big 1 << 32) - big 1);
	return (ns, real (uu >> 8) / 16777216.0);
}

# ----------------------------------------------------------------------------
# sampling

sample_argmax(p: array of real, n: int): int
{
	max_i := 0;
	max_p := p[0];
	for(i := 1; i < n; i++)
		if(p[i] > max_p){
			max_i = i;
			max_p = p[i];
		}
	return max_i;
}

sample_mult(p: array of real, n: int, coin: real): int
{
	cdf := 0.0;
	for(i := 0; i < n; i++){
		cdf += p[i];
		if(coin < cdf)
			return i;
	}
	return n - 1;
}

# top-p (nucleus) sampling with custom in-place quicksort
sample_topp(p: array of real, n: int, topp: real, pi: array of ProbIndex, coin: real): int
{
	n0 := 0;
	cutoff := (1.0 - topp) / real (n - 1);
	for(i := 0; i < n; i++){
		if(p[i] >= cutoff){
			pi[n0].index = i;
			pi[n0].prob = p[i];
			n0++;
		}
	}
	probindex_sort(pi, 0, n0 - 1);

	cumulative := 0.0;
	last_idx := n0 - 1;
	for(j := 0; j < n0; j++){
		cumulative += pi[j].prob;
		if(cumulative > topp){
			last_idx = j;
			break;
		}
	}
	r := coin * cumulative;
	cdf := 0.0;
	for(k := 0; k <= last_idx; k++){
		cdf += pi[k].prob;
		if(r < cdf)
			return pi[k].index;
	}
	return pi[last_idx].index;
}

# quicksort ProbIndex by probability descending
probindex_sort(a: array of ProbIndex, lo, hi: int)
{
	if(lo >= hi)
		return;
	pivot := a[(lo + hi) / 2].prob;
	i := lo;
	j := hi;
	while(i <= j){
		while(a[i].prob > pivot)
			i++;
		while(a[j].prob < pivot)
			j--;
		if(i <= j){
			tmp := a[i];
			a[i] = a[j];
			a[j] = tmp;
			i++;
			j--;
		}
	}
	probindex_sort(a, lo, j);
	probindex_sort(a, i, hi);
}

build_sampler(vocab_size: int, temperature, topp: real, rng_seed: big): ref Sampler
{
	s := ref Sampler;
	s.vocab_size = vocab_size;
	s.temperature = temperature;
	s.topp = topp;
	s.rng_state = rng_seed;
	s.probindex = array[vocab_size] of ProbIndex;
	return s;
}

Sampler.sample(s: self ref Sampler, logits: array of real): int
{
	if(s.temperature == 0.0)
		return sample_argmax(logits, s.vocab_size);

	for(q := 0; q < s.vocab_size; q++)
		logits[q] /= s.temperature;
	softmax(logits, 0, s.vocab_size);
	(ns, coin) := random_f32(s.rng_state);
	s.rng_state = ns;

	if(s.topp <= 0.0 || s.topp >= 1.0)
		return sample_mult(logits, s.vocab_size, coin);
	return sample_topp(logits, s.vocab_size, s.topp, s.probindex, coin);
}

# ----------------------------------------------------------------------------
# checkpoint loading

build_transformer(path: string): (ref Transformer, string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return (nil, sys->sprint("cannot open %s: %r", path));

	(ok, d) := sys->fstat(fd);
	if(ok < 0)
		return (nil, "fstat failed");
	file_size := d.length;

	# 7 ints = 28 bytes header
	hdr := array[28] of byte;
	if(fullread(fd, hdr, 28) < 0)
		return (nil, "short config read");

	cfg: Config;
	cfg.dim        = bytes_to_int(hdr,  0);
	cfg.hidden_dim = bytes_to_int(hdr,  4);
	cfg.n_layers   = bytes_to_int(hdr,  8);
	cfg.n_heads    = bytes_to_int(hdr, 12);
	cfg.n_kv_heads = bytes_to_int(hdr, 16);
	cfg.vocab_size = bytes_to_int(hdr, 20);
	cfg.seq_len    = bytes_to_int(hdr, 24);

	shared_weights := 1;
	if(cfg.vocab_size < 0){
		cfg.vocab_size = -cfg.vocab_size;
		shared_weights = 0;
	}

	wbytes := int (file_size - big 28);
	if(wbytes <= 0)
		return (nil, "no weights in file");
	raw := array[wbytes] of byte;
	if(fullread(fd, raw, wbytes) < 0)
		return (nil, "short weights read");

	# memory-map style: build the Weights structure with views into raw
	w: Weights;
	head_size := cfg.dim / cfg.n_heads;
	off := 0;

	w.token_embedding = read_floats(raw, off, cfg.vocab_size * cfg.dim);
	off += cfg.vocab_size * cfg.dim * 4;

	w.rms_att_weight = read_floats(raw, off, cfg.n_layers * cfg.dim);
	off += cfg.n_layers * cfg.dim * 4;

	w.wq = read_floats(raw, off, cfg.n_layers * cfg.dim * (cfg.n_heads * head_size));
	off += cfg.n_layers * cfg.dim * (cfg.n_heads * head_size) * 4;

	w.wk = read_floats(raw, off, cfg.n_layers * cfg.dim * (cfg.n_kv_heads * head_size));
	off += cfg.n_layers * cfg.dim * (cfg.n_kv_heads * head_size) * 4;

	w.wv = read_floats(raw, off, cfg.n_layers * cfg.dim * (cfg.n_kv_heads * head_size));
	off += cfg.n_layers * cfg.dim * (cfg.n_kv_heads * head_size) * 4;

	w.wo = read_floats(raw, off, cfg.n_layers * (cfg.n_heads * head_size) * cfg.dim);
	off += cfg.n_layers * (cfg.n_heads * head_size) * cfg.dim * 4;

	w.rms_ffn_weight = read_floats(raw, off, cfg.n_layers * cfg.dim);
	off += cfg.n_layers * cfg.dim * 4;

	w.w1 = read_floats(raw, off, cfg.n_layers * cfg.dim * cfg.hidden_dim);
	off += cfg.n_layers * cfg.dim * cfg.hidden_dim * 4;

	w.w2 = read_floats(raw, off, cfg.n_layers * cfg.hidden_dim * cfg.dim);
	off += cfg.n_layers * cfg.hidden_dim * cfg.dim * 4;

	w.w3 = read_floats(raw, off, cfg.n_layers * cfg.dim * cfg.hidden_dim);
	off += cfg.n_layers * cfg.dim * cfg.hidden_dim * 4;

	w.rms_final_weight = read_floats(raw, off, cfg.dim);
	off += cfg.dim * 4;

	# skip freq_cis_real and freq_cis_imag
	off += cfg.seq_len * head_size / 2 * 4;
	off += cfg.seq_len * head_size / 2 * 4;

	if(shared_weights){
		w.wcls = w.token_embedding;
	} else {
		w.wcls = read_floats(raw, off, cfg.vocab_size * cfg.dim);
	}

	# allocate run state
	state: State;
	kv_dim := (cfg.dim * cfg.n_kv_heads) / cfg.n_heads;
	state.x         = array[cfg.dim] of real;
	state.xb        = array[cfg.dim] of real;
	state.xb2       = array[cfg.dim] of real;
	state.hb        = array[cfg.hidden_dim] of real;
	state.hb2       = array[cfg.hidden_dim] of real;
	state.q         = array[cfg.dim] of real;
	state.att       = array[cfg.n_heads * cfg.seq_len] of real;
	state.logits    = array[cfg.vocab_size] of real;
	state.key_cache   = array[cfg.n_layers * cfg.seq_len * kv_dim] of real;
	state.value_cache = array[cfg.n_layers * cfg.seq_len * kv_dim] of real;

	# zero-initialise (Limbo guarantees zero for new arrays of real, but be
	# explicit because some hosts may not).
	zero(state.x);
	zero(state.xb);
	zero(state.xb2);
	zero(state.hb);
	zero(state.hb2);
	zero(state.q);
	zero(state.att);
	zero(state.logits);
	zero(state.key_cache);
	zero(state.value_cache);

	t := ref Transformer;
	t.config = cfg;
	t.w = w;
	t.s = state;
	return (t, nil);
}

zero(a: array of real)
{
	for(i := 0; i < len a; i++)
		a[i] = 0.0;
}

# ----------------------------------------------------------------------------
# forward pass

Transformer.forward(t: self ref Transformer, token, pos: int): array of real
{
	p := t.config;
	w := t.w;
	s := t.s;

	dim := p.dim;
	kv_dim := (dim * p.n_kv_heads) / p.n_heads;
	kv_mul := p.n_heads / p.n_kv_heads;
	hidden_dim := p.hidden_dim;
	head_size := dim / p.n_heads;

	# embed token
	for(ie := 0; ie < dim; ie++)
		s.x[ie] = w.token_embedding[token*dim + ie];

	for(l := 0; l < p.n_layers; l++){
		# attention rmsnorm into xb
		rmsnorm_off(s.xb, s.x, w.rms_att_weight, l*dim, dim);

		# qkv projections
		matmul(s.q, s.xb, w.wq, l*dim*dim, dim, dim);

		loff := l * p.seq_len * kv_dim;
		# write k, v directly into the cache at slot pos
		k_base := loff + pos * kv_dim;
		v_base := loff + pos * kv_dim;
		matmul_into(s.key_cache,   k_base, s.xb, w.wk, l*dim*kv_dim, dim, kv_dim);
		matmul_into(s.value_cache, v_base, s.xb, w.wv, l*dim*kv_dim, dim, kv_dim);

		# RoPE relative positional encoding
		for(ir := 0; ir < dim; ir += 2){
			head_dim := ir % head_size;
			freq := 1.0 / math->pow(10000.0, real head_dim / real head_size);
			val := real pos * freq;
			fcr := math->cos(val);
			fci := math->sin(val);
			rotn := 1;
			if(ir < kv_dim)
				rotn = 2;
			for(rv := 0; rv < rotn; rv++){
				if(rv == 0){
					v0 := s.q[ir];
					v1 := s.q[ir+1];
					s.q[ir]   = v0*fcr - v1*fci;
					s.q[ir+1] = v0*fci + v1*fcr;
				} else {
					v0 := s.key_cache[k_base + ir];
					v1 := s.key_cache[k_base + ir + 1];
					s.key_cache[k_base + ir]     = v0*fcr - v1*fci;
					s.key_cache[k_base + ir + 1] = v0*fci + v1*fcr;
				}
			}
		}

		# multi-head attention
		for(h := 0; h < p.n_heads; h++){
			q_off := h * head_size;
			att_off := h * p.seq_len;
			kv_head_off := (h / kv_mul) * head_size;
			for(tt := 0; tt <= pos; tt++){
				k_off := loff + tt * kv_dim + kv_head_off;
				score := 0.0;
				for(i := 0; i < head_size; i++)
					score += s.q[q_off + i] * s.key_cache[k_off + i];
				score /= math->sqrt(real head_size);
				s.att[att_off + tt] = score;
			}
			softmax(s.att, att_off, pos + 1);

			xb_off := h * head_size;
			for(i := 0; i < head_size; i++)
				s.xb[xb_off + i] = 0.0;
			for(tt = 0; tt <= pos; tt++){
				v_off := loff + tt * kv_dim + kv_head_off;
				a := s.att[att_off + tt];
				for(i := 0; i < head_size; i++)
					s.xb[xb_off + i] += a * s.value_cache[v_off + i];
			}
		}

		# output projection
		matmul(s.xb2, s.xb, w.wo, l*dim*dim, dim, dim);

		# residual
		for(i := 0; i < dim; i++)
			s.x[i] += s.xb2[i];

		# ffn rmsnorm
		rmsnorm_off(s.xb, s.x, w.rms_ffn_weight, l*dim, dim);

		# ffn
		matmul(s.hb,  s.xb, w.w1, l*dim*hidden_dim, dim, hidden_dim);
		matmul(s.hb2, s.xb, w.w3, l*dim*hidden_dim, dim, hidden_dim);

		# SwiGLU
		for(i = 0; i < hidden_dim; i++){
			val := s.hb[i];
			val *= 1.0 / (1.0 + math->exp(-val));
			val *= s.hb2[i];
			s.hb[i] = val;
		}

		# project back
		matmul(s.xb, s.hb, w.w2, l*dim*hidden_dim, hidden_dim, dim);

		# residual
		for(i = 0; i < dim; i++)
			s.x[i] += s.xb[i];
	}

	# final rmsnorm
	rmsnorm_off(s.x, s.x, w.rms_final_weight, 0, dim);

	# classifier into logits
	matmul(s.logits, s.x, w.wcls, 0, dim, p.vocab_size);
	return s.logits;
}

# rmsnorm where weight starts at woff
rmsnorm_off(o, x, weight: array of real, woff, size: int)
{
	ss := 0.0;
	for(j := 0; j < size; j++)
		ss += x[j] * x[j];
	ss /= real size;
	ss += 1.0e-5;
	ss = 1.0 / math->sqrt(ss);
	for(j = 0; j < size; j++)
		o[j] = weight[woff + j] * (ss * x[j]);
}

# matmul into out[off:off+d]
matmul_into(out: array of real, off: int, x, w: array of real, woff, n, d: int)
{
	for(i := 0; i < d; i++){
		val := 0.0;
		base := woff + i*n;
		for(j := 0; j < n; j++)
			val += w[base + j] * x[j];
		out[off + i] = val;
	}
}

# ----------------------------------------------------------------------------
# tokenizer
#
# vocab entries are stored as `array of byte`, never as Limbo strings:
# the llama tokenizer's byte-fallback entries hold raw bytes that are
# not valid UTF-8 (e.g. 0xC0) and round-tripping them through `string`
# would collapse them onto U+FFFD.

build_tokenizer(path: string, vocab_size: int): (ref Tokenizer, string)
{
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil)
		return (nil, sys->sprint("cannot open %s: %r", path));

	hdr := array[4] of byte;
	if(fullread(fd, hdr, 4) < 0)
		return (nil, "tokenizer: short header");
	max_token_length := bytes_to_int(hdr, 0);

	t := ref Tokenizer;
	t.vocab_size = vocab_size;
	t.max_token_length = max_token_length;
	t.vocab = array[vocab_size] of array of byte;
	t.vocab_scores = array[vocab_size] of real;

	hdrf := array[8] of byte;
	for(i := 0; i < vocab_size; i++){
		if(fullread(fd, hdrf, 8) < 0)
			return (nil, "tokenizer: short entry header");
		t.vocab_scores[i] = math->bits32real(bytes_to_int(hdrf, 0));
		slen := bytes_to_int(hdrf, 4);
		buf := array[slen] of byte;
		if(slen > 0 && fullread(fd, buf, slen) < 0)
			return (nil, "tokenizer: short entry body");
		t.vocab[i] = buf;
	}
	return (t, nil);
}

# byte-array compare: returns -1, 0, +1
bcmp(a, b: array of byte): int
{
	la := len a;
	lb := len b;
	n := la;
	if(lb < n)
		n = lb;
	for(i := 0; i < n; i++){
		ai := int a[i];
		bi := int b[i];
		if(ai < bi)
			return -1;
		if(ai > bi)
			return 1;
	}
	if(la < lb) return -1;
	if(la > lb) return 1;
	return 0;
}

bconcat(a, b: array of byte): array of byte
{
	out := array[len a + len b] of byte;
	out[0:] = a;
	out[len a:] = b;
	return out;
}

Tokenizer.decode(t: self ref Tokenizer, prev_token, token: int): array of byte
{
	piece := t.vocab[token];
	# BOS strips leading space
	if(prev_token == 1 && len piece > 0 && int piece[0] == ' ')
		piece = piece[1:];
	# raw byte form: <0xXX>
	if(len piece >= 6
	   && int piece[0] == '<' && int piece[1] == '0' && int piece[2] == 'x'
	   && int piece[5] == '>'){
		c1 := hexval(int piece[3]);
		c2 := hexval(int piece[4]);
		if(c1 >= 0 && c2 >= 0){
			out := array[1] of byte;
			out[0] = byte (c1 * 16 + c2);
			return out;
		}
	}
	return piece;
}

hexval(c: int): int
{
	if(c >= '0' && c <= '9')
		return c - '0';
	if(c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if(c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

ensure_sorted(t: ref Tokenizer)
{
	if(t.sorted_vocab != nil)
		return;
	t.sorted_vocab = array[t.vocab_size] of TokenIndex;
	for(i := 0; i < t.vocab_size; i++){
		t.sorted_vocab[i].s = t.vocab[i];
		t.sorted_vocab[i].id = i;
	}
	tokenindex_sort(t.sorted_vocab, 0, t.vocab_size - 1);
}

tokenindex_sort(a: array of TokenIndex, lo, hi: int)
{
	if(lo >= hi)
		return;
	pivot := a[(lo + hi) / 2].s;
	i := lo;
	j := hi;
	while(i <= j){
		while(bcmp(a[i].s, pivot) < 0)
			i++;
		while(bcmp(a[j].s, pivot) > 0)
			j--;
		if(i <= j){
			tmp := a[i];
			a[i] = a[j];
			a[j] = tmp;
			i++;
			j--;
		}
	}
	tokenindex_sort(a, lo, j);
	tokenindex_sort(a, i, hi);
}

byte_lookup(s: array of byte, sv: array of TokenIndex, n: int): int
{
	lo := 0;
	hi := n - 1;
	while(lo <= hi){
		mid := (lo + hi) / 2;
		c := bcmp(s, sv[mid].s);
		if(c == 0)
			return sv[mid].id;
		if(c < 0)
			hi = mid - 1;
		else
			lo = mid + 1;
	}
	return -1;
}

Tokenizer.encode(tk: self ref Tokenizer, text: string, bos, eos: int): array of int
{
	ensure_sorted(tk);

	# convert the prompt to its UTF-8 byte representation
	bytes := array of byte text;
	nbytes := len bytes;

	tokens := array[nbytes + 3] of int;
	n := 0;

	if(bos)
		tokens[n++] = 1;

	# leading dummy space prefix
	if(nbytes > 0){
		sp := array[1] of byte;
		sp[0] = byte ' ';
		id := byte_lookup(sp, tk.sorted_vocab, tk.vocab_size);
		if(id != -1)
			tokens[n++] = id;
	}

	# walk input one UTF-8 codepoint at a time
	buf := array[8] of byte;
	blen := 0;
	for(c := 0; c < nbytes; c++){
		# start of a new codepoint (byte not a UTF-8 continuation)
		if((int bytes[c] & 16rC0) != 16r80)
			blen = 0;
		buf[blen++] = bytes[c];
		# if the next byte is a continuation and we have headroom, keep going
		if(c + 1 < nbytes && (int bytes[c+1] & 16rC0) == 16r80 && blen < 4)
			continue;
		# look up the codepoint as bytes
		key := array[blen] of byte;
		key[0:] = buf[0:blen];
		id := byte_lookup(key, tk.sorted_vocab, tk.vocab_size);
		if(id != -1){
			tokens[n++] = id;
		} else {
			# fall back to byte tokens (id = byte + 3)
			for(k := 0; k < blen; k++)
				tokens[n++] = (int buf[k]) + 3;
		}
		blen = 0;
	}

	# BPE merge loop
	for(;;){
		best_score := -1.0e10;
		best_id := -1;
		best_idx := -1;
		for(i := 0; i < n - 1; i++){
			pair := bconcat(tk.vocab[tokens[i]], tk.vocab[tokens[i+1]]);
			id := byte_lookup(pair, tk.sorted_vocab, tk.vocab_size);
			if(id != -1 && tk.vocab_scores[id] > best_score){
				best_score = tk.vocab_scores[id];
				best_id = id;
				best_idx = i;
			}
		}
		if(best_idx == -1)
			break;
		tokens[best_idx] = best_id;
		for(i = best_idx + 1; i < n - 1; i++)
			tokens[i] = tokens[i+1];
		n--;
	}

	if(eos)
		tokens[n++] = 2;

	out := array[n] of int;
	for(i := 0; i < n; i++)
		out[i] = tokens[i];
	return out;
}

# ----------------------------------------------------------------------------
# top-level generate

generate(t: ref Transformer, tk: ref Tokenizer, sa: ref Sampler, prompt: string, steps: int)
{
	if(prompt == nil)
		prompt = "";

	prompt_tokens := tk.encode(prompt, 1, 0);
	num_prompt := len prompt_tokens;
	if(num_prompt < 1){
		sys->fprint(stderr, "expected at least 1 prompt token\n");
		return;
	}

	start := 0;
	token := prompt_tokens[0];
	pos := 0;
	while(pos < steps){
		logits := t.forward(token, pos);
		next: int;
		if(pos < num_prompt - 1)
			next = prompt_tokens[pos + 1];
		else
			next = sa.sample(logits);
		pos++;
		if(next == 1)
			break;

		piece := tk.decode(token, next);
		safe_write(piece);
		token = next;

		if(start == 0)
			start = sys->millisec();
	}
	sys->print("\n");
	if(pos > 1){
		end := sys->millisec();
		dt := end - start;
		if(dt <= 0)
			dt = 1;
		sys->fprint(stderr, "achieved tok/s: %f\n",
			real (pos - 1) * 1000.0 / real dt);
	}
}

# write piece bytes to stdout, suppressing non-printable single-byte controls
safe_write(piece: array of byte)
{
	if(piece == nil || len piece == 0)
		return;
	if(len piece == 1){
		c := int piece[0];
		if(!(c >= 16r20 && c < 16r7f) && c != '\t' && c != '\n' && c != '\r' && c != ' ')
			return;
	}
	sys->write(stdout, piece, len piece);
}
