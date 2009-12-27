//-------------------------------------------------------------------------
//File:   InputBuffer.cpp
//Author: Baoguang Yang
//
//Copyright (c) 2009 S3Graphics Corporation. All rights reserved.
//
//Contains code maintaining input buffer of shadow algorithms.
//It is a utility for deferred shading style rendering.
//Three buffers are rendered: Position/Normal/TexturedColor
//We dont render TexCoord buffer, because doing so would make
//texture access complicated: we have to know IDs of various textures. 
//-------------------------------------------------------------------------

#pragma once

#include "CommonDef.h"
#include "MRTRenderObject.h"
#include "DepthObject.h"
#include "OGRE_LAYOUT.h"


class InputBuffer
{
public:
	ID3D10Effect		*m_pEffect;
	ID3D10InputLayout	*m_pMaxLayout;
	MRTRenderObject		*m_pInputAttributes;	
	DepthObject			*m_pDepthBuffer;


	InputBuffer();
	HRESULT OnD3D10CreateDevice(ID3D10Device* pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void* pUserContext);
	void OnD3D10FrameRender(bool par_RenderWarrior, 
							bool par_RenderStaticObjs, 
							CDXUTDialog &par_SampleUI,
							S3UTMesh &par_MeshScene,
							S3UTCamera &par_CameraRef,
							ID3D10Device* pDev10, 
							double fTime, 
							float fElapsedTime, 
							void* pUserContext);
	void OnD3D10DestroyDevice( void* pUserContext = NULL );
	HRESULT OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
	void	OnD3D10SwapChainReleasing( void* pUserContext );
	~InputBuffer();

};

InputBuffer::InputBuffer()
{
	m_pEffect = NULL;
	m_pMaxLayout = NULL;
	m_pInputAttributes = NULL;
	m_pDepthBuffer = NULL;

}
InputBuffer::~InputBuffer()
{
	//OnD3D10DestroyDevice();
};

HRESULT InputBuffer::OnD3D10CreateDevice(	ID3D10Device *pDev10, 
											const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, 
											void *pUserContext
										)
{
	HRESULT hr;
	// create effect
    static const D3D10_INPUT_ELEMENT_DESC scenemeshlayout[] =
    {
        { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },
        { "NORMAL", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D10_INPUT_PER_VERTEX_DATA, 0 },
        { "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 24, D3D10_INPUT_PER_VERTEX_DATA, 0 },
    };

    WCHAR str[MAX_PATH];
    V_RETURN(DXUTFindDXSDKMediaFileCch(str, MAX_PATH, (INPUT_BUFFER_EFFECT_FILE_NAME) ));
    ID3D10Blob *pErrors;
    if (D3DX10CreateEffectFromFile(		str, NULL, NULL, "fx_4_0", 
										D3D10_SHADER_DEBUG|D3D10_SHADER_SKIP_OPTIMIZATION, 0, 
										pDev10, NULL, NULL, &m_pEffect, &pErrors, &hr) != S_OK	)
    {
        MessageBoxA(NULL, (char *)pErrors->GetBufferPointer(), "Compilation error", MB_OK);
        exit(0);
    }
    D3D10_PASS_DESC PassDesc;
    V_RETURN(m_pEffect->GetTechniqueByName("RenderInputAttriTech_StaticObj")->GetPassByIndex(0)->GetDesc(&PassDesc));
    V_RETURN(pDev10->CreateInputLayout(scenemeshlayout, 3, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &m_pMaxLayout));
	
	m_pInputAttributes = new MRTRenderObject( "RenderInputAttriTech_StaticObj" );
	m_pInputAttributes ->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);

	m_pDepthBuffer = new DepthObject( "RenderInputAttriTech_StaticObj" );
	m_pDepthBuffer ->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);
	return S_OK;

}
void	InputBuffer::OnD3D10SwapChainReleasing( void* pUserContext )
{
	m_pInputAttributes->OnD3D10SwapChainReleasing( pUserContext );
	m_pDepthBuffer->OnD3D10SwapChainReleasing( pUserContext );
}

HRESULT InputBuffer::OnD3D10SwapChainResized( ID3D10Device* pDev10, 
											  IDXGISwapChain *pSwapChain, 
											  const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
	D3D10_TEXTURE2D_DESC texDescPos =
	{
		pBackBufferSurfaceDesc->Width, //UINT Width;
		pBackBufferSurfaceDesc->Height, //UINT Height;
		1,//UINT MipLevels;
		1,//UINT ArraySize;
		DXGI_FORMAT_R32G32B32A32_FLOAT,//DXGI_FORMAT Format;
		{1, 0}, //DXGI_SAMPLE_DESC SampleDesc;
		D3D10_USAGE_DEFAULT, //D3D10_USAGE Usage;
		D3D10_BIND_SHADER_RESOURCE | D3D10_BIND_RENDER_TARGET ,//UINT BindFlags;
		0,//UINT CPUAccessFlags;
		0,//UINT MiscFlags;
	};
	D3D10_TEXTURE2D_DESC texDescClrNorm =
	{
		pBackBufferSurfaceDesc->Width, //UINT Width;
		pBackBufferSurfaceDesc->Height, //UINT Height;
		1,//UINT MipLevels;
		1,//UINT ArraySize;
		DXGI_FORMAT_R32G32B32A32_FLOAT,//DXGI_FORMAT Format;
		{1, 0}, //DXGI_SAMPLE_DESC SampleDesc;
		D3D10_USAGE_DEFAULT, //D3D10_USAGE Usage;
		D3D10_BIND_SHADER_RESOURCE | D3D10_BIND_RENDER_TARGET ,//UINT BindFlags;
		0,//UINT CPUAccessFlags;
		0,//UINT MiscFlags;
	};

	m_pInputAttributes->OnD3D10SwapChainResized( texDescPos,
												 texDescClrNorm,
												 texDescClrNorm,
												 texDescClrNorm,
												 pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	//only position need 32 bit floating point, 16bit is enouth for others. save memory/traffic.

	D3D10_TEXTURE2D_DESC texDescDepthBuffer =
	{
		pBackBufferSurfaceDesc->Width, //UINT Width;
		pBackBufferSurfaceDesc->Height, //UINT Height;
		1,//UINT MipLevels;
		1,//UINT ArraySize;
		DXGI_FORMAT_D32_FLOAT,//DXGI_FORMAT Format;
		{1, 0}, //DXGI_SAMPLE_DESC SampleDesc;
		D3D10_USAGE_DEFAULT, //D3D10_USAGE Usage;
		D3D10_BIND_DEPTH_STENCIL ,//UINT BindFlags;
		0,//UINT CPUAccessFlags;
		0,//UINT MiscFlags;
	};
	m_pDepthBuffer->OnD3D10SwapChainResized( texDescDepthBuffer, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	return S_OK;
}

void InputBuffer::OnD3D10FrameRender(	bool par_RenderOgre, 
										bool par_RenderStaticObjs, 
										CDXUTDialog &par_SampleUI,
										S3UTMesh &par_MeshScene,
										S3UTCamera &par_CameraRef,
										ID3D10Device* pDev10, 
										double fTime, 
										float fElapsedTime, 
										void* pUserContext
									)
{
	HRESULT hr;
    D3DXMATRIX mTmp, mWorldView, mWorldViewProj, mWorldViewInv;
    D3DXMatrixInverse(&mTmp, NULL, par_CameraRef.GetWorldMatrix());
    D3DXMatrixMultiply(&mWorldView, &mTmp, par_CameraRef.GetViewMatrix());

    D3DXMatrixMultiply(&mWorldViewProj, &mWorldView, par_CameraRef.GetProjMatrix());
    D3DXMatrixInverse(&mWorldViewInv, NULL, &mWorldView);

	pDev10->IASetInputLayout(m_pMaxLayout);//seems useless, remove this sooner or later
    
    unsigned iTmp = par_SampleUI.GetCheckBox(IDC_BTEXTURED)->GetChecked();
    V(m_pEffect->GetVariableByName("bTextured")->AsScalar()->SetRawValue(&iTmp, 0, sizeof(iTmp)));
    V(m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&mWorldViewProj));
	
	ID3D10EffectShaderResourceVariable *pTexture = m_pEffect->GetVariableByName("DiffuseTex")->AsShaderResource();
	
	m_pDepthBuffer->Clear(pDev10);
	m_pInputAttributes->OnD3D10FrameRender(	m_pEffect,
											m_pEffect->GetTechniqueByName(	SUIT_DEFERRED_SHADING_TECH_NAME ),
											m_pEffect->GetTechniqueByName(	SKIN_DEFERRED_SHADING_TECH_NAME ),
											m_pEffect->GetTechniqueByName(	STATIC_OBJ_DEFERRED_SHADING_TECH_NAME ),
											&mWorldViewProj,
											&par_MeshScene,
											m_pDepthBuffer->m_pDSView,
											pDev10, fTime, fElapsedTime, pUserContext);


	
}

void InputBuffer::OnD3D10DestroyDevice( void* pUserContext )
{
	OnD3D10SwapChainReleasing(NULL);

    SAFE_RELEASE(m_pEffect);
    SAFE_RELEASE(m_pMaxLayout);
	m_pInputAttributes->OnD3D10DestroyDevice();
	SAFE_DELETE(m_pInputAttributes);

	m_pDepthBuffer->OnD3D10DestroyDevice();
	SAFE_DELETE(m_pDepthBuffer);
}

