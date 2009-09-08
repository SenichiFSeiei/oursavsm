// Returns coordinates for the four pixels surround a given fragment.
// Given and returned Coords are normalized
// These are given by (in Fetch4 order) - where "R" is the returned value:
//   - R + (1, 0)
//   - R + (0, 1)
//   - R + (1, 1)
//   - R
// Also returns bilinear weights in the output parameter.
int3 GetBilCoordsAndWeights(float2 Coords, float2 TexSize, out float4 Weights)
{
    float2 TexelSize = 1 / TexSize;
    float2 TexelCoords = Coords * TexSize;
    
    // Compute weights
    Weights.xy = frac(TexelCoords + 0.5);
    Weights.zw = 1 - Weights.xy;
    Weights = Weights.xzxz * Weights.wyyw;
    
    // Compute upper-left pixel coordinates
    // NOTE: D3D texel alignment...
    return int3(floor(TexelCoords),0);
}

