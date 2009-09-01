


#define FP32_MAN_BITS      23u       
#define FP32_EXP_BITS       8u       
#define FP32_BITS          32u       
#define FP32_EXP_BIAS     127u       

#define FP6E5_MAN_BITS      6u       
#define FP6E5_EXP_BITS      5u       
#define FP6E5_BITS         11u       
#define FP6E5_EXP_BIAS     15u       

#define FP5E5_MAN_BITS      5u       
#define FP5E5_EXP_BITS      5u       
#define FP5E5_BITS         10u       
#define FP5E5_EXP_BIAS     15u       

//#########################################################################################################3
static inline UINT packFP32FloatToM6E5Float( UINT val )
{
    UINT data, exp, man;

    // Extract the exponent and the MAN_BITS MSBs of the mantissa from the fp32
    // number.
    exp = (val >> FP32_MAN_BITS) & 255;
    man = (val >> (FP32_MAN_BITS - FP6E5_MAN_BITS)) & ((1u << FP6E5_MAN_BITS) - 1);

    // Round mantissa
    if (val & 1u << ((FP32_MAN_BITS - FP6E5_MAN_BITS) - 1u)) {
        man++;
        if (man & (1u << FP6E5_MAN_BITS)) {
            man = 0;
            exp++;
        }
    }

    if (exp <= FP32_EXP_BIAS - FP6E5_EXP_BIAS ) {
		// Denorm.
        if (exp < (FP32_EXP_BIAS - FP6E5_EXP_BIAS - FP6E5_MAN_BITS)) {
            data = 0;          
        } else {
            data = (man | 1u << FP6E5_MAN_BITS) >> (FP32_EXP_BIAS - FP6E5_EXP_BIAS + 1 - exp);
        }
    } else if (exp > FP32_EXP_BIAS + FP6E5_EXP_BIAS ) {
        // |x| > 2^15, overflow, an existing INF, or NaN.  
        if (exp == (1u<<FP32_EXP_BITS)-1) {
            if (man) {
                data = (1u<<(FP6E5_EXP_BITS + FP6E5_MAN_BITS)) - 1;
                // Return allows -NaN to return as NaN even if there is no sign bit.
                return data | ((val >> (FP32_BITS - FP6E5_BITS)) & (1u << (FP32_MAN_BITS + FP32_EXP_BITS)));
            } else {
                data = (((1u << FP6E5_EXP_BITS)-1) << FP6E5_MAN_BITS);
            }
        } else {
            data = ((((1u << FP6E5_EXP_BITS) -1 ) << FP6E5_MAN_BITS) - (1u<<FP6E5_MAN_BITS)) | ( (1u << FP6E5_MAN_BITS) -1 );
        }
    } else {
        exp -= FP32_EXP_BIAS - FP6E5_EXP_BIAS;
        data = (exp << FP6E5_MAN_BITS) | man;
    }

    if (val & 1u << (FP32_MAN_BITS + FP32_EXP_BITS)) {
        // Clamp negative values
        data = 0;        
    }

    return data;
}



//#########################################################################################################3
static inline UINT packFP32FloatToM5E5Float( UINT val)
{
    UINT data, exp, man;

    // Extract the exponent and the MAN_BITS MSBs of the mantissa from the fp32
    // number.
    exp = (val >> FP32_MAN_BITS) & 255;
    man = (val >> (FP32_MAN_BITS - FP5E5_MAN_BITS)) & ((1u << FP5E5_MAN_BITS) - 1);

    // Round mantissa
    if (val & 1u << ((FP32_MAN_BITS - FP5E5_MAN_BITS) - 1u)) {
        man++;
        if (man & (1u << FP5E5_MAN_BITS)) {
            man = 0;
            exp++;
        }
    }

    if (exp <= FP32_EXP_BIAS - FP5E5_EXP_BIAS ) {
		// Denorm.
        if (exp < (FP32_EXP_BIAS - FP5E5_EXP_BIAS - FP5E5_MAN_BITS)) {
            data = 0;          
        } else {
            data = (man | 1u << FP5E5_MAN_BITS) >> (FP32_EXP_BIAS - FP5E5_EXP_BIAS + 1 - exp);
        }
    } else if (exp > FP32_EXP_BIAS + FP5E5_EXP_BIAS ) {
        // |x| > 2^15, overflow, an existing INF, or NaN.  
        if (exp == (1u<<FP32_EXP_BITS)-1) {
            if (man) {
                data = (1u<<(FP5E5_EXP_BITS + FP5E5_MAN_BITS)) - 1;
                // Return allows -NaN to return as NaN even if there is no sign bit.
                return data | ((val >> (FP32_BITS - FP5E5_BITS)) & (1u << (FP32_MAN_BITS + FP32_EXP_BITS)));
            } else {
                data = (((1u << FP5E5_EXP_BITS)-1) << FP5E5_MAN_BITS);
            }
        } else {
            data = ((((1u << FP5E5_EXP_BITS) -1 ) << FP5E5_MAN_BITS) - (1u<<FP5E5_MAN_BITS)) | ( (1u << FP5E5_MAN_BITS) -1 );
        }
    } else {
        exp -= FP32_EXP_BIAS - FP5E5_EXP_BIAS;
        data = (exp << FP5E5_MAN_BITS) | man;
    }

    if (val & 1u << (FP32_MAN_BITS + FP32_EXP_BITS)) {
        // Clamp negative values
        data = 0;        
    }

    return data;
}



