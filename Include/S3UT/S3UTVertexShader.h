#pragma once
//----------------------------------------------------------------------------------
// File:   S3UTVertexShader.h
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


#include "S3UTShader.h"

/*
    This is a simple wrapper for compiling and loading a vertex shader for use in the S3Graphics DX10 SDK.  
    It's only purpose is to wrap up common operations to allow the main sample code to be more readable.
*/
class S3UTVertexShader : public S3UTShader
{
public:

    S3UTVertexShader();
    ~S3UTVertexShader();

    /*
        Load, Compile, and Create a Vertex Shader from an HLSL shader text file.
    */
    HRESULT CreateFromFile(ID3D10Device* pd3dDevice, LPCWSTR pSrcFile, CONST D3D10_SHADER_MACRO* pDefines,
        LPCSTR pFunctionName, LPCSTR pProfile, UINT Flags1, UINT Flags2);

    void Release();

    UINT GetVertexSize(){return m_VertexSize;}
    UINT GetVertexElementCount(){return m_NumIEDElements;}
    D3D10_INPUT_ELEMENT_DESC *GetInputElementLayout(){return m_pIEDLayout;}
    ID3D10InputLayout* GetInputLayout(){return m_pInputLayout;}
    ID3D10VertexShader *GetVS(){return m_pVS;};
    
public:
    ID3D10VertexShader *m_pVS;

    UINT m_NumIEDElements;
    D3D10_INPUT_ELEMENT_DESC *m_pIEDLayout;
    ID3D10InputLayout *m_pInputLayout;

    UINT m_VertexSize;
};