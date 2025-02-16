#ifndef Pontus_H
#define Pontus_H
#include <vector>
#include <unordered_set>
#include <utility>
#include <cstring>
#include <cmath>
#include <iostream>
#include <fstream>
#include <algorithm>
#include "datatypes.hpp"
extern "C"
{
#include "hash.h"
#include "util.h"
}

class Pontus
{

    typedef struct SBUCKET_type
    {
        short int count;
        unsigned char key[LGN];
        uint8_t status;
        uint8_t substractflag;
    } SBucket;

    struct pontus_type
    {

        // Counter to count total degree
        val_tp sum;
        // Counter table
        SBucket **counts;

        // Outer sketch depth and width
        int depth;
        int width;

        // # key word bits
        int lgn;

        unsigned long *hash, *scale, *hardner;
    };

public:
    Pontus(int depth, int width, int lgn);

    ~Pontus();

    void Update(unsigned char *key, val_tp value);

    val_tp PointQuery(unsigned char *key);

    void NewWindow();

    val_tp QueryL2(unsigned char *key);

    val_tp Low_estimate(unsigned char *key);

    val_tp Up_estimate(unsigned char *key);

    val_tp GetCount();

    void Reset();

private:
    void SetBucket(int row, int column, val_tp sum, long count, unsigned char *key);

    Pontus::SBucket **GetTable();

    pontus_type pontus_;
};

#endif
