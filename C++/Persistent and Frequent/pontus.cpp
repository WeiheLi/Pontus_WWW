#include "pontus.hpp"
#include <math.h>

int seeds = 0;
int ct = 0;
static int flag = 0;
static int replacement_count = 0;

pontus::pontus(int depth, int width, int lgn)
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
	char name[] = "pontus";
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

pontus::~pontus()
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

void pontus::Update(unsigned char *key, val_tp val)
{
	unsigned long bucket = 0;
	unsigned long bucket1 = 0;
	int keylen = pontus_.lgn / 8;
	pontus_.sum += 1;
	pontus::SBucket *sbucket;
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
		if (sbucket->key[0] == '\0')
		{
			memcpy(sbucket->key, key, keylen);
			flag = 1;
			if (sbucket->status == 0)
			{
				sbucket->count = 1;
			}
			sbucket->status = 1;
			sbucket->count_h = 1;
			return;
		}
		else if (memcmp(key, sbucket->key, keylen) == 0)
		{
			sbucket->count_h += 1;
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
			if (sbucket->count_h >= 65536)
				sbucket->count_h = 65536;

			return;
		}
		if (sbucket->count + sbucket->count_h < min)
		{
			min = sbucket->count + sbucket->count_h;
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

		if (sbucket->count + sbucket->count_h >= 0)
		{
			int divisor = sbucket->count + sbucket->count_h + 1;
			int f = rand() % divisor;
			if (f >= divisor - 1)
			{
				{
					sbucket->count -= 1;
					sbucket->count_h -= 1;
					sbucket->substractflag = 1;
				}

				if (sbucket->count <= 0)
				{
					memcpy(sbucket->key, key, keylen);
					sbucket->count = 1;
					sbucket->count_h = 1;
					sbucket->status = 1;
				}
			}
		}
	}
}

void pontus::Query(val_tp thresh, val_tp thresh_h, std::vector<std::pair<key_tp, val_tp>> &results)
{
	myset res;
	for (int i = 0; i < pontus_.width * pontus_.depth; i++)
	{
		if (pontus_.counts[i]->count > (int)thresh && pontus_.counts[i]->count_h > (int)thresh_h)
		{
			key_tp reskey;
			memcpy(reskey.key, pontus_.counts[i]->key, pontus_.lgn / 8);
			std::pair<key_tp, val_tp> node;
			node.first = reskey;
			node.second = pontus_.counts[i]->count;
			results.push_back(node);
		}
	}
}

void pontus::NewWindow()
{
	for (int i = 0; i < pontus_.depth * pontus_.width; i++)
	{
		pontus_.counts[i]->status = 0;
		pontus_.counts[i]->substractflag = 0;
	}
}

val_tp pontus::PointQuery(unsigned char *key)
{
	return Low_estimate(key);
}

val_tp pontus::Low_estimate(unsigned char *key)
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

val_tp pontus::Up_estimate(unsigned char *key)
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

val_tp pontus::GetCount()
{
	return pontus_.sum;
}

void pontus::Reset()
{
	pontus_.sum = 0;
	for (int i = 0; i < pontus_.depth * pontus_.width; i++)
	{
		pontus_.counts[i]->count = 0;
		memset(pontus_.counts[i]->key, 0, pontus_.lgn / 8);
	}
}

void pontus::SetBucket(int row, int column, val_tp sum, long count, unsigned char *key)
{
	int index = row * pontus_.width + column;
	pontus_.counts[index]->count = count;
	memcpy(pontus_.counts[index]->key, key, pontus_.lgn / 8);
}

pontus::SBucket **pontus::GetTable()
{
	return pontus_.counts;
}