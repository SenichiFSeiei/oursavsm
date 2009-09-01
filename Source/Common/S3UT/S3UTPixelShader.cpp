//----------------------------------------------------------------------------------
// File:   S3UTPixelShader.cpp
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

#include "DXUT.h"
#include "S3UTPixelShader.h"

S3UTPixelShader::S3UTPixelShader(): S3UTShader()
{


    m_pPS = NULL;
}

S3UTPixelShader::~S3UTPixelShader()
{
}

HRESULT S3UTPixelShader::CreateFromFile(ID3D10Device* pd3dDevice, LPCWSTR pSrcFile, CONST D3D10_SHADER_MACRO* pDefines,
    LPCSTR pFunctionName, LPCSTR pProfile, UINT Flags1, UINT Flags2)
{
    HRESULT hr;
    // Inherited compile and reflect
    V(CompileShader(pd3dDevice,pSrcFile,pDefines,pFunctionName,pProfile,Flags1,Flags2));

    V(pd3dDevice->CreatePixelShader(m_pShaderByteCode->GetBufferPointer(),m_pShaderByteCode->GetBufferSize(),&m_pPS));
    return hr;
}

void S3UTPixelShader::Release()
{
    S3UTShader::Release();
    SAFE_RELEASE(m_pPS);
}
