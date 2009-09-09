//----------------------------------------------------------------------------------
// File:   HDRCubeTexture.cpp
// 
// Copyright (c) 2007 S3Graphics Corporation. All rights reserved.
//
// TO  THE MAXIMUM  EXTENT PERMITTED  BY APPLICABLE  LAW, THIS SOFTWARE  IS PROVIDED
// *AS IS*  AND S3Graphics AND  ITS SUPPLIERS DISCLAIM  ALL WARRANTIES,  EITHER  EXPRESS
// OR IMPLIED, INCLUDING, BUT NOT LIMITED  TO, IMPLIED WARRANTIES OF MERCHANTABILITY
// AND FITNESS FOR A PARTICULAR PURPOSE.  IN NO EVENT SHALL  S3Graphics OR ITS SUPPLIERS
// BE  LIABLE  FOR  ANY  SPECIAL,  INCIDENTAL,  INDIRECT,  OR  CONSEQUENTIAL DAMAGES
// WHATSOEVER (INCLUDING, WITHOUT LIMITATION,  DAMAGES FOR LOSS OF BUSINESS PROFITS,
// BUSINESS INTERRUPTION, LOSS OF BUSINESS INFORMATION, OR ANY OTHER PECUNIARY LOSS)
// ARISING OUT OF THE  USE OF OR INABILITY  TO USE THIS SOFTWARE, EVEN IF S3Graphics HAS
// BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
//
//
//----------------------------------------------------------------------------------

// Desc: Class for dealing with HDR textures

#include "HDRCubeTexture.h"
#include "rgbe.h"
#include "FloatPack.h"

#define RGB16_MAX             100
#define RGB32_MAX             10000
#define LOG2(x) (log10(x) / log10(2.000000))

//-----------------------------------------------------------------------------
// Name: 
//-----------------------------------------------------------------------------
HDRCubeTexture::HDRCubeTexture()
{
    m_D3DDevice = NULL;
    m_Texture     = NULL;
    m_TextureRV   = NULL;

    m_data  = NULL;
    m_width = m_height = 0;

    m_max_r = m_max_g = m_max_b = 0.0;
    m_min_r = m_min_g = m_min_b = 1e10;
    m_max   = 0;

    m_PowsOfTwo = new double[257];
    for( int i=0; i <= 256; i++ ){
        m_PowsOfTwo[i] = powf( 2.0f, (float)(i - 128) );
    }
}

//-----------------------------------------------------------------------------
// Name: 
//-----------------------------------------------------------------------------
HDRCubeTexture::~HDRCubeTexture()
{
    // Free the HDR-RGBE bitmap
    SAFE_DELETE_ARRAY(m_data);
    SAFE_DELETE_ARRAY(m_PowsOfTwo);
}

//-----------------------------------------------------------------------------
// Name: OnDestroyDevice
//-----------------------------------------------------------------------------
HRESULT HDRCubeTexture::OnCreateDevice(ID3D10Device* pd3dDevice, WCHAR *filename, 
                                       DXGI_FORMAT format){
    HRESULT hr;

    m_D3DDevice = pd3dDevice;

    LoadHDRCubeTexture( filename );

    // Let's create initially a R32G32B32A32F cube texture and decode the RGBE 
    // "cross-shaped" image into it. Then we will proceed to convert to the 
    // necessary formats if different from the original.
    CreateMipmappedStaggingRGBA32Texture( );

    hr = EncodeHDRTexture(format);

    return hr;
}

//-----------------------------------------------------------------------------
// Name: OnDestroyDevice
//-----------------------------------------------------------------------------
void HDRCubeTexture::OnDestroyDevice()
{
    SAFE_RELEASE( m_Texture );	
    SAFE_RELEASE( m_TextureRV );
    SAFE_RELEASE( m_StagingTexture );	
}

//-----------------------------------------------------------------------------
// Name: encodeHDRTexture
// Desc: Create a copy of the input floating-point texture with RGB9E5, RGB16,
//       or RGB32 encoding (note this is operating on cube textures)
//-----------------------------------------------------------------------------
HRESULT HDRCubeTexture::EncodeHDRTexture( DXGI_FORMAT format )
{
    HRESULT hr = S_OK;

    // Free the resources of the old texture, but keep the staging one.
    SAFE_RELEASE( m_Texture );	
    SAFE_RELEASE( m_TextureRV );

    int pixelDepth = 16;

    DXGI_FORMAT destFormat = DXGI_FORMAT_UNKNOWN;

    switch(format){
        case DXGI_FORMAT_R8G8B8A8_UNORM:
            destFormat = DXGI_FORMAT_R8G8B8A8_UNORM; 
            pixelDepth = 4;
            break;
        case DXGI_FORMAT_R9G9B9E5_SHAREDEXP:
            destFormat = DXGI_FORMAT_R9G9B9E5_SHAREDEXP; 
            pixelDepth = 4;
            break;
        case DXGI_FORMAT_R11G11B10_FLOAT:
            destFormat = DXGI_FORMAT_R11G11B10_FLOAT; 
            pixelDepth = 4;
            break;
        case DXGI_FORMAT_R16G16B16A16_FLOAT: 
            destFormat = DXGI_FORMAT_R16G16B16A16_FLOAT; 
            pixelDepth = 8;
            break;
        case DXGI_FORMAT_R32G32B32A32_FLOAT: 
            destFormat = DXGI_FORMAT_R32G32B32A32_FLOAT; 
            pixelDepth = 16;
            break;
    }

    if( FAILED( hr ) ){ 
        MessageBox(NULL, L"HDRCubeTexture: Format not supported!!!", L"ERROR", 
            MB_OK|MB_SETFOREGROUND|MB_TOPMOST);		
        return FALSE;
    }

    // Create the final texture 
    D3D10_TEXTURE2D_DESC dstex;

    dstex.Width              = min(4096,m_StagingTextureDesc.Width);
    dstex.Height             = min(4096,m_StagingTextureDesc.Height);
    dstex.MipLevels          = m_StagingTextureDesc.MipLevels;
    dstex.ArraySize          = m_StagingTextureDesc.ArraySize;
    dstex.Format             = destFormat;
    dstex.SampleDesc.Count   = m_StagingTextureDesc.SampleDesc.Count;
    dstex.SampleDesc.Quality = m_StagingTextureDesc.SampleDesc.Quality;
    dstex.Usage              = D3D10_USAGE_DEFAULT;
    dstex.BindFlags          = D3D10_BIND_SHADER_RESOURCE;
    dstex.CPUAccessFlags     = 0;
    dstex.MiscFlags          = D3D10_RESOURCE_MISC_TEXTURECUBE; 

    hr = m_D3DDevice->CreateTexture2D( &dstex, NULL, &m_Texture );

    if( FAILED( hr ) ){ 
        MessageBox(NULL, L"HDRCubeTexture: Failed to create final texture!!!", 
            L"ERROR", MB_OK|MB_SETFOREGROUND|MB_TOPMOST);		
        return FALSE;
    }

    D3D10_MAPPED_TEXTURE2D stagingMap;

    unsigned int subSurfaceID, sizeFace;
    unsigned char* buffer;
    void* convertedData = NULL;

    buffer = new unsigned char[m_StagingTextureDesc.Width * m_StagingTextureDesc.Height * pixelDepth];

    for( UINT i = 0; i < dstex.ArraySize; i++){
        {
            for( UINT j = 0; j < dstex.MipLevels; j++){
                subSurfaceID = D3D10CalcSubresource( j, i, m_StagingTextureDesc.MipLevels );
                sizeFace     = (m_StagingTextureDesc.Width >> j) * (m_StagingTextureDesc.Height >> j);

                m_StagingTexture->Map( subSurfaceID, D3D10_MAP_READ, 0, &stagingMap);

                // Pick the different encoding schemes
                switch(destFormat){
                   case DXGI_FORMAT_R8G8B8A8_UNORM: 
                       ConvertRGBA32ToR8G8B8A8Array( (unsigned int*) buffer, (float*) stagingMap.pData, sizeFace );
                       convertedData = (void*) buffer;
                   break;
                   case DXGI_FORMAT_R9G9B9E5_SHAREDEXP: 
                       ConvertRGBA32ToRGB9E5Array( (unsigned int*) buffer, (float*) stagingMap.pData, sizeFace );
                       convertedData = (void*) buffer;
                   break;
                   case DXGI_FORMAT_R11G11B10_FLOAT: 
                       ConvertRGBA32ToR11G11B10Array( (unsigned int*) buffer, (float*) stagingMap.pData, sizeFace );
                       convertedData = (void*) buffer;
                   break;
                   case DXGI_FORMAT_R16G16B16A16_FLOAT: 
                       D3DXFloat32To16Array( (D3DXFLOAT16*) buffer, (float*) stagingMap.pData, sizeFace * 4);
                       convertedData = (void*) buffer;
                   break;
                   case DXGI_FORMAT_R32G32B32A32_FLOAT: 
                       convertedData = (void*) stagingMap.pData;
                   break;
                }

                // Update the destination texture
                m_D3DDevice->UpdateSubresource( m_Texture, subSurfaceID, NULL, 
                    convertedData, ( stagingMap.RowPitch / 16 ) * pixelDepth, 0); 

                // Free the mapping
                m_StagingTexture->Unmap(subSurfaceID);
            }
        }
    }

    SAFE_DELETE_ARRAY(buffer);

    // Create the resource and fill the mip chain
    D3D10_SHADER_RESOURCE_VIEW_DESC SRVDesc;

    SRVDesc.Format                      = dstex.Format;
    SRVDesc.ViewDimension               = D3D10_SRV_DIMENSION_TEXTURECUBE;
    SRVDesc.TextureCube.MipLevels       = dstex.MipLevels;
    SRVDesc.TextureCube.MostDetailedMip = 0;

    hr = m_D3DDevice->CreateShaderResourceView( m_Texture, &SRVDesc, &m_TextureRV );

    m_TexFormat = format;

    if( FAILED( hr ) ){ 
        MessageBox(NULL, L"HDRCubeTexture: Format not supported!!!", L"ERROR", 
            MB_OK|MB_SETFOREGROUND|MB_TOPMOST);		
        return FALSE;
    }

    return S_OK;
}


//-----------------------------------------------------------------------------
// Name: encodeHDRTexture
// Desc:     
//-----------------------------------------------------------------------------
HRESULT HDRCubeTexture::CreateMipmappedStaggingRGBA32Texture( ){
    HRESULT hr = S_OK;

    int face_width  = m_width / 3;
    int face_height = m_height / 4;
    int pixelDepth  = 16;

    ID3D10Texture2D *tempTexture;

    // Create the texture 
    D3D10_TEXTURE2D_DESC dstex;

    dstex.Width              = face_width;
    dstex.Height             = face_height;
    dstex.MipLevels          = (int)LOG2(1.0*face_width);
    dstex.ArraySize          = 6;
    dstex.Format             = DXGI_FORMAT_R32G32B32A32_FLOAT;
    dstex.SampleDesc.Count   = 1;
    dstex.SampleDesc.Quality = 0;  
    dstex.Usage              = D3D10_USAGE_DEFAULT;
    dstex.BindFlags          = D3D10_BIND_SHADER_RESOURCE | D3D10_BIND_RENDER_TARGET;
    dstex.CPUAccessFlags     = 0;
    dstex.MiscFlags          = D3D10_RESOURCE_MISC_TEXTURECUBE | D3D10_RESOURCE_MISC_GENERATE_MIPS; 

    hr |= m_D3DDevice->CreateTexture2D( &dstex, NULL, &tempTexture );

    if( FAILED( hr ) ){ 
        MessageBox(NULL, L"HDRCubeTexture: Failed to create staging resource!!!", L"ERROR", 
            MB_OK|MB_SETFOREGROUND|MB_TOPMOST);		
        return FALSE;
    }

    unsigned char *subResourceArray, *pDest;

    subResourceArray = new unsigned char[face_width * face_height * pixelDepth];

    // Fill each face of the cubemap
    for(int faceID = D3D10_TEXTURECUBE_FACE_POSITIVE_X; faceID <= D3D10_TEXTURECUBE_FACE_NEGATIVE_Z; faceID++){
        int           xx=0, yy=0;
        float         r, g, b;

        pDest = subResourceArray;

        UINT iSubResource = D3D10CalcSubresource( 0, faceID, dstex.MipLevels );

        for (int j=0; j<face_height; j++) {
            switch(faceID){
            case D3D10_TEXTURECUBE_FACE_POSITIVE_X: 	yy = m_height - (face_height + j + 1); break;
            case D3D10_TEXTURECUBE_FACE_NEGATIVE_X: 	yy = m_height - (face_height + j + 1); break;
            case D3D10_TEXTURECUBE_FACE_POSITIVE_Y: 	yy = 3 * face_height + j; break;
            case D3D10_TEXTURECUBE_FACE_NEGATIVE_Y: 	yy = face_height + j; break;
            case D3D10_TEXTURECUBE_FACE_POSITIVE_Z: 	yy = j; break;
            case D3D10_TEXTURECUBE_FACE_NEGATIVE_Z: 	yy = m_height - (face_height + j + 1); break;
            }

            for (int i=0; i<face_width; i++) {
                switch(faceID){
                case D3D10_TEXTURECUBE_FACE_POSITIVE_X: 	xx = i; break;
                case D3D10_TEXTURECUBE_FACE_NEGATIVE_X: 	xx = 2 * face_width + i; break;
                case D3D10_TEXTURECUBE_FACE_POSITIVE_Y: 	xx = 2 * face_width - (i + 1); break;
                case D3D10_TEXTURECUBE_FACE_NEGATIVE_Y: 	xx = 2 * face_width - (i + 1); break;
                case D3D10_TEXTURECUBE_FACE_POSITIVE_Z: 	xx = 2 * face_width - (i + 1); break;
                case D3D10_TEXTURECUBE_FACE_NEGATIVE_Z: 	xx = face_width + i; break;
                } 

                rgbe2float(&r, &g, &b, m_data + ((m_width * (m_height - 1 - yy)) + xx) * 4);

                EncodeRGBA32( &pDest, r, g, b );
            }
        }

        // Fill level 0 of the mip chain for each face
        m_D3DDevice->UpdateSubresource( tempTexture, iSubResource, NULL, subResourceArray, face_width * pixelDepth, 0); 
    }

    SAFE_DELETE_ARRAY(subResourceArray);

    // Create the resource and fill the mip chain
    D3D10_SHADER_RESOURCE_VIEW_DESC SRVDesc;

    SRVDesc.Format                      = dstex.Format;
    SRVDesc.ViewDimension               = D3D10_SRV_DIMENSION_TEXTURECUBE;
    SRVDesc.TextureCube.MipLevels       = dstex.MipLevels;
    SRVDesc.TextureCube.MostDetailedMip = 0;

    ID3D10ShaderResourceView *tempSRV;

    hr |= m_D3DDevice->CreateShaderResourceView( tempTexture, &SRVDesc, &tempSRV );
    m_D3DDevice->GenerateMips( tempSRV );

    SAFE_RELEASE( tempSRV );

    // Create the staging texture and copy over all the data
    m_StagingTextureDesc.Width              = dstex.Width;
    m_StagingTextureDesc.Height             = dstex.Height;
    m_StagingTextureDesc.MipLevels          = dstex.MipLevels;
    m_StagingTextureDesc.ArraySize          = dstex.ArraySize;
    m_StagingTextureDesc.Format             = dstex.Format;
    m_StagingTextureDesc.SampleDesc.Count   = dstex.SampleDesc.Count;
    m_StagingTextureDesc.SampleDesc.Quality = dstex.SampleDesc.Quality;
    m_StagingTextureDesc.Usage              = D3D10_USAGE_STAGING;
    m_StagingTextureDesc.BindFlags          = 0;
    m_StagingTextureDesc.CPUAccessFlags     = D3D10_CPU_ACCESS_WRITE | D3D10_CPU_ACCESS_READ;
    m_StagingTextureDesc.MiscFlags          = D3D10_RESOURCE_MISC_TEXTURECUBE; 

    hr |= m_D3DDevice->CreateTexture2D( &m_StagingTextureDesc, NULL, &m_StagingTexture );

    m_D3DDevice->CopyResource( m_StagingTexture, tempTexture );

    SAFE_RELEASE( tempTexture );

    if( FAILED( hr ) ){ 
        MessageBox(NULL, L"HDRCubeTexture: Error creating the staging texture!!!", L"ERROR", MB_OK|MB_SETFOREGROUND|MB_TOPMOST);		
        return hr;
    }
    return S_OK;
}

//--------------------------------------------------------------------------------------
void HDRCubeTexture::EncodeRGBA32( BYTE** ppDest, float r, float g, float b )
{
    // Store
    float* pDestColor = (float*) *ppDest;
    *pDestColor++ = r;
    *pDestColor++ = g;
    *pDestColor++ = b;
    *pDestColor++ = 0.333f*(r+g+b)/m_max;

    *ppDest += 4 * sizeof(float);
}


//--------------------------------------------------------------------------------------
inline int log2_ceiling( float val, double *powsOfTwo)
{
    int iMax = 256;
    int iMin = 0;

    while( iMax - iMin > 1 )
    {
        int iMiddle = (iMax + iMin) / 2;

        if( val > powsOfTwo[iMiddle] )
            iMin = iMiddle;
        else
            iMax = iMiddle;
    }

    return iMax - 128;
}

void HDRCubeTexture::ConvertRGBA32ToRGB9E5Array( unsigned int *pOut, float *pIn, UINT n){
    float r, g, b;
    unsigned int* DestColor;

    // n should indicate the number of 4-vec rgb values, i.e. teh number of pixels!

    DestColor = pOut;
    for( unsigned int i = 0; i < n; i++){
        r = pIn[i*4 + 0];
        g = pIn[i*4 + 1];
        b = pIn[i*4 + 2];

        // Determine the largest color component
        float maxComponent = max( max(r, g), b );

        // Round to the nearest integer exponent
        int nExp = log2_ceiling(maxComponent, m_PowsOfTwo);
        nExp = max( nExp, -15 );	//keep us in the -15 to 16 range
        nExp = min( nExp, 16 );

        // Divide the components by the shared exponent
        FLOAT fDivisor = (FLOAT) m_PowsOfTwo[ nExp+128 ];

        r /= fDivisor;
        g /= fDivisor;
        b /= fDivisor;

        // Constrain the color components
        r = max( 0, min(1, r) );
        g = max( 0, min(1, g) );
        b = max( 0, min(1, b) );

        // Store the shared exponent in the alpha channel
        *DestColor = ((nExp+15) & 31) << 27;
        *DestColor |= ((UINT)(b*511) & 511) << 18;
        *DestColor |= ((UINT)(g*511) & 511) << 9;
        *DestColor |= ((UINT)(r*511) & 511);

        DestColor++;
    }
}

void HDRCubeTexture::ConvertRGBA32ToR8G8B8A8Array( unsigned int *pOut, float *pIn, UINT n){
    unsigned int r, g, b;
    unsigned int* DestColor;

    // n should indicate the number of 4-vec rgb values, i.e. the number of pixels!
    DestColor = pOut;
    for( unsigned int i = 0; i < n; i++){
        // Clamp the color components
        r = (int) (255.0f * max( 0, min(1.0, pIn[i*4 + 0]) ));
        g = (int) (255.0f * max( 0, min(1.0, pIn[i*4 + 1]) ));
        b = (int) (255.0f * max( 0, min(1.0, pIn[i*4 + 2]) ));

        // Store the shared exponent in the alpha channel

        *DestColor  = r;
        *DestColor |= g << 8;
        *DestColor |= b << 16;
        *DestColor |= 0xff000000;

        DestColor++;
    }
}
//--------------------------------------------------------------------------------------
void HDRCubeTexture::ConvertRGBA32ToR11G11B10Array( unsigned int *pOut, float *pIn, UINT n ){
    unsigned int r, g, b;
    unsigned int* DestColor;

    // n should indicate the number of 4-vec rgb values, i.e. teh number of pixels!

    DestColor = pOut;
    for( unsigned int i = 0; i < n; i++){
        r = packFP32FloatToM6E5Float( *(UINT*)&pIn[i*4 + 0] );
        g = packFP32FloatToM6E5Float( *(UINT*)&pIn[i*4 + 1] );
        b = packFP32FloatToM5E5Float( *(UINT*)&pIn[i*4 + 2] );

        *DestColor  = r;
        *DestColor |= g << 11;
        *DestColor |= b << 22;

        DestColor++;
    }
}




//-----------------------------------------------------------------------------
// Name: 
//-----------------------------------------------------------------------------
bool HDRCubeTexture::LoadHDRCubeTexture(WCHAR* filename)
{
    if(m_data != NULL){
        SAFE_DELETE_ARRAY(m_data);
        m_data = NULL;
    }

    // Load the file
    FILE *fp;

    _wfopen_s(&fp, filename, L"rb");

    if (!fp) {
        fprintf(stderr, "Error opening file '%s'\n", filename);
        return false;
    }

    rgbe_header_info header;

    if (RGBE_ReadHeader(fp, &m_width, &m_height, &header))
        return false;

    m_data = new unsigned char[m_width*m_height*4];
    if (!m_data)
        return false;

    if (RGBE_ReadPixels_Raw_RLE(fp, m_data, m_width, m_height))
        return false;

    fclose(fp);

    // Analyze the values
    int i;
    float r, g, b;

    unsigned char e;
    unsigned char mine = 255;
    unsigned char maxe = 0;
    unsigned char *ptr = m_data;

    for(i=0; i<m_width*m_height; i++) {
        r = *(ptr + 0);
        g = *(ptr + 1);
        b = *(ptr + 2);
        e = *(ptr + 3);
        if (e < mine) mine = e;
        if (e > maxe) maxe = e;

        rgbe2float(&r, &g, &b, ptr);
        if (r > m_max_r) 
            m_max_r = r;
        if (g > m_max_g) 
            m_max_g = g;
        if (b > m_max_b) 
            m_max_b = b;
        if (r < m_min_r)
            m_min_r = r;
        if (g < m_min_g) 
            m_min_g = g;
        if (b < m_min_b) 
            m_min_b = b;

        ptr += 4;
    }

    m_max = m_max_r;
    if (m_max_g > m_max) 
        m_max = m_max_g;
    if (m_max_b > m_max) 
        m_max = m_max_b;

    return true;
}


