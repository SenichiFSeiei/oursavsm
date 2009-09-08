//----------------------------------------------------------------------------------
// File:   HDRCubeTexture.h
// Author: Miguel Sainz
// Email:  sdkfeedback@S3Graphics.com
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

#ifndef _HDRCUBETEXTURE_H
#define _HDRCUBETEXTURE_H

#include <DXUT.h>
#include <SDKmisc.h>
#include <d3d10.h>
#include <d3dx10.h>

class HDRCubeTexture {
public:
    HDRCubeTexture();
    ~HDRCubeTexture();

    HRESULT OnCreateDevice      (ID3D10Device* pd3dDevice, WCHAR *filename, DXGI_FORMAT format);
    void    OnDestroyDevice     ();

    HRESULT EncodeHDRTexture( DXGI_FORMAT format );


    ID3D10Texture2D           *m_Texture;
    ID3D10ShaderResourceView  *m_TextureRV;

    DXGI_FORMAT m_TexFormat;

private:
    bool LoadHDRCubeTexture(WCHAR* filename);

    HRESULT CreateMipmappedStaggingRGBA32Texture( );

    void EncodeRGBA32( BYTE** ppDest, float r, float g, float b );
    void ConvertRGBA32ToRGB9E5Array   ( unsigned int *pOut, float *pIn, UINT n );
    void ConvertRGBA32ToR11G11B10Array( unsigned int *pOut, float *pIn, UINT n );
    void ConvertRGBA32ToR8G8B8A8Array ( unsigned int *pOut, float *pIn, UINT n );

    ID3D10Device*  m_D3DDevice;

    // hdr file data
    int m_width, m_height;
    unsigned char *m_data;

    float m_max_r, m_max_g, m_max_b;
    float m_min_r, m_min_g, m_min_b;
    float m_max;

    // Lookup table for log calculations (from MS DX10 SDK)
    double *m_PowsOfTwo; 

    // Staging texture with everything converted to R32G32B32A32.
    ID3D10Texture2D          *m_StagingTexture;
    D3D10_TEXTURE2D_DESC      m_StagingTextureDesc;
};

#endif

