#include "Pontus.hpp"
#include <math.h>
int seeds = 0;
int ct = 0;
static int flag = 0;

Pontus::Pontus(int depth, int width, int lgn)
{

	pontus_.depth = depth;
	pontus_.width = width;
	pontus_.lgn = lgn;
	pontus_.sum = 0;
	pontus_.counts = new SBucket *[depth * width];
	for (int i = 0; i < depth * width; i++)
	{
		pontus_.counts[i] = (SBucket *)calloc(1, sizeof(SBucket));
		memset(pontus_.counts[i], 0, sizeof(SBucket));
		pontus_.counts[i]->key[0] = '\0';
	}

	pontus_.hash = new unsigned long[depth];
	pontus_.scale = new unsigned long[depth];
	pontus_.hardner = new unsigned long[depth];
	char name[] = "Pontus";
	unsigned long seed = AwareHash((unsigned char *)name, strlen(name), 13091204281, 228204732751, 6620830889);
	for (int i = 0; i < depth; i++)
	{
		pontus_.hash[i] = GenHashSeed(seed++);
	}
	for (int i = 0; i < depth; i++)
	{
		pontus_.scale[i] = GenHashSeed(seed++);
	}
	for (int i = 0; i < depth; i++)
	{
		pontus_.hardner[i] = GenHashSeed(seed++);
	}
}

Pontus::~Pontus()
{
	for (int i = 0; i < pontus_.depth * pontus_.width; i++)
	{
		free(pontus_.counts[i]);
	}
	delete[] pontus_.hash;
	delete[] pontus_.scale;
	delete[] pontus_.hardner;
	delete[] pontus_.counts;
}

void Pontus::Update(unsigned char *key, val_tp val)
{
	unsigned long bucket = 0;
	unsigned long bucket1 = 0;
	int keylen = pontus_.lgn / 8;
	pontus_.sum += 1;
	Pontus::SBucket *sbucket;
	int flag = 0;
	long min = 99999999;
	int loc = -1;
	int loc1 = -1;
	int k;
	int index;
	int ii = 0;
	for (int i = 0; i < pontus_.depth; i++)
	{
		bucket = MurmurHash64A(key, keylen, pontus_.hardner[i]) % pontus_.width;
		index = i * pontus_.width + bucket;
		sbucket = pontus_.counts[index];
		if (sbucket->key[0] == '\0' && sbucket->count == 0 && sbucket->status == 0)
		{
			memcpy(sbucket->key, key, keylen);
			flag = 1;
			sbucket->status = 1;
			sbucket->count = 1;
			return;
		}
		else if (memcmp(key, sbucket->key, keylen) == 0)
		{
			if (sbucket->status == 0)
			{
				flag = 1;
				if (sbucket->substractflag == 1)
				{
					sbucket->count += 2;
				}
				if (sbucket->substractflag == 0)
				{
					sbucket->count += 1;
				}
				sbucket->status = 1;
			}
			return;
		}
		if (sbucket->count < min)
		{
			min = sbucket->count;
			loc = index;
		}
	}
	if (flag == 0 && loc >= 0)
	{
		sbucket = pontus_.counts[loc];
		if (sbucket->status == 1 || sbucket->substractflag == 1)
		{
			return;
		}

		k = rand() % (1 << 11);
		int threshold = (1 << 11) / (sbucket->count + 1);
		if (k < (int)((threshold)))
		{
			sbucket->count -= 1;
			sbucket->substractflag = 1;
			if (sbucket->count <= 0)
			{
				memcpy(sbucket->key, key, keylen);
				sbucket->count = 1;
				sbucket->status = 1;
			}
		}
	}
}

val_tp Pontus::QueryL2(unsigned char *key)
{
	unsigned long bucket = 0;
	unsigned long col = 0;
	int flag_q = 0;
	Pontus::SBucket *sbucket;
	int keylen = pontus_.lgn / 8;
	int index;
	val_tp min_val = 8888888;

	for (int i = 0; i < pontus_.depth; i++)
	{
		bucket = MurmurHash64A(key, keylen, pontus_.hardner[i]) % pontus_.width;
		index = i * pontus_.width + bucket;
		sbucket = pontus_.counts[index];

		if (memcmp(key, sbucket->key, keylen) == 0)
		{
			flag_q = 1;
			return pontus_.counts[index]->count;
		}

		if (sbucket->count < min_val)
		{
			min_val = pontus_.counts[index]->count;
		}
	}

	if (flag_q == 0)
	{
		return min_val;
	}
}

void Pontus::NewWindow()
{
	for (int i = 0; i < pontus_.depth * pontus_.width; i++)
	{
		pontus_.counts[i]->status = 0;
		pontus_.counts[i]->substractflag = 0;
	}
}

val_tp Pontus::PointQuery(unsigned char *key)
{
	return Low_estimate(key);
}

val_tp Pontus::Low_estimate(unsigned char *key)
{

	val_tp ret = 0, max = 0, min = 999999999;
	for (int i = 0; i < pontus_.depth; i++)
	{
		unsigned long bucket = MurmurHash64A(key, pontus_.lgn / 8, pontus_.hardner[i]) % pontus_.width;

		unsigned long index = i * pontus_.width + bucket;
		if (memcmp(pontus_.counts[index]->key, key, pontus_.lgn / 8) == 0)
		{
			max += pontus_.counts[index]->count;
		}
		index = i * pontus_.width + (bucket + 1) % pontus_.width;
		if (memcmp(key, pontus_.counts[i]->key, pontus_.lgn / 8) == 0)
		{
			max += pontus_.counts[index]->count;
		}
	}
	return max;
}

val_tp Pontus::Up_estimate(unsigned char *key)
{

	val_tp ret = 0, max = 0, min = 999999999;
	for (int i = 0; i < pontus_.depth; i++)
	{
		unsigned long bucket = MurmurHash64A(key, pontus_.lgn / 8, pontus_.hardner[i]) % pontus_.width;

		unsigned long index = i * pontus_.width + bucket;
		if (memcmp(pontus_.counts[index]->key, key, pontus_.lgn / 8) == 0)
		{
			max += pontus_.counts[index]->count;
		}
		if (pontus_.counts[index]->count < min)
			min = pontus_.counts[index]->count;
		index = i * pontus_.width + (bucket + 1) % pontus_.width;
		if (memcmp(key, pontus_.counts[i]->key, pontus_.lgn / 8) == 0)
		{
			max += pontus_.counts[index]->count;
		}
	}
	if (max)
		return max;
	return min;
}

val_tp Pontus::GetCount()
{
	return pontus_.sum;
}

void Pontus::Reset()
{
	pontus_.sum = 0;
	for (int i = 0; i < pontus_.depth * pontus_.width; i++)
	{
		pontus_.counts[i]->count = 0;
		memset(pontus_.counts[i]->key, 0, pontus_.lgn / 8);
	}
}

void Pontus::SetBucket(int row, int column, val_tp sum, long count, unsigned char *key)
{
	int index = row * pontus_.width + column;
	pontus_.counts[index]->count = count;
	memcpy(pontus_.counts[index]->key, key, pontus_.lgn / 8);
}

Pontus::SBucket **Pontus::GetTable()
{
	return pontus_.counts;
}