//-------------------------------------------------------------------------
//File:   MRTRenderObject.cpp
//Author: Baoguang Yang
//
//Copyright (c) 2009 S3Graphics Corporation. All rights reserved.
//
//This is an MRT version of RenderObject
//The only difference of it from RenderObject is that it utilizes MRT
//-------------------------------------------------------------------------


#ifndef MRT_RO
#define MRT_RO

#include <dxut.h>
#include <dxutgui.h>
#include <dxutsettingsdlg.h>
#include <sdkmisc.h>

#include <S3UTmesh.h>
#include "CommonDef.h"

#define NUM_RT 4

class MRTRenderObject{
public:

	MRTRenderObject( char *TechName );
	~MRTRenderObject();

	HRESULT OnD3D10CreateDevice( ID3D10Effect	*pEffect, ID3D10Device* pDev10, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
	HRESULT OnD3D10SwapChainResized(	D3D10_TEXTURE2D_DESC par_Tex0desc,
										D3D10_TEXTURE2D_DESC par_Tex1desc,
										D3D10_TEXTURE2D_DESC par_Tex2desc,
										D3D10_TEXTURE2D_DESC par_Tex3desc,
										ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, 
										const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );

	void	OnD3D10FrameRender(		ID3D10Effect *m_pEffect,
									ID3D10EffectTechnique *pSuitKernelTech,
									ID3D10EffectTechnique *pBodyKernelTech,
									ID3D10EffectTechnique *pSceneKernelTech,
									D3DXMATRIX *pWorldViewProj,
									S3UTMesh *MeshScene, 
									ID3D10DepthStencilView *pDSV, 
									ID3D10Device* pDev10, 
									double fTime, float fElapsedTime, void* pUserContext, float r=0,float g=0,float b=0,float a = 0 );
	void	OnD3D10SwapChainReleasing( void* pUserContext );
	void	OnD3D10DestroyDevice( void* pUserContext = NULL );
	void	DumpFrameResult( ID3D10Texture2D *pSrcTex,WCHAR *FileName,ID3D10Device* pDev10 );

	ID3D10Texture2D				*m_pTexture0;
	ID3D10Texture2D				*m_pTexture1;
	ID3D10Texture2D				*m_pTexture2;
	ID3D10Texture2D				*m_pTexture3;

	D3D10_TEXTURE2D_DESC		 m_Tex0Desc;
	D3D10_TEXTURE2D_DESC		 m_Tex1Desc;
	D3D10_TEXTURE2D_DESC		 m_Tex2Desc;
	D3D10_TEXTURE2D_DESC		 m_Tex3Desc;

	ID3D10RenderTargetView		*m_pRTView0;
	ID3D10RenderTargetView		*m_pRTView1;
	ID3D10RenderTargetView		*m_pRTView2;
	ID3D10RenderTargetView		*m_pRTView3;
	
	ID3D10ShaderResourceView	*m_pSRView0;
	ID3D10ShaderResourceView	*m_pSRView1;
	ID3D10ShaderResourceView	*m_pSRView2;
	ID3D10ShaderResourceView	*m_pSRView3;

	ID3D10InputLayout			*m_pLayout;
	ID3D10Effect				*m_pEffect;
	char						*m_pTechniqueName;
	D3D10_VIEWPORT				 m_Viewport;

};

MRTRenderObject::MRTRenderObject( char *TechName )
{
	m_pTechniqueName = TechName;
	m_pEffect		 = NULL;
	
	m_pTexture0		 = NULL;
	m_pTexture1		 = NULL;
	m_pTexture2		 = NULL;
	m_pTexture3		 = NULL;
	
	m_pRTView0		 = NULL;
	m_pRTView1		 = NULL;
	m_pRTView2		 = NULL;
	m_pRTView3		 = NULL;

	m_pSRView0		 = NULL;
	m_pSRView1		 = NULL;
	m_pSRView2		 = NULL;
	m_pSRView3		 = NULL;

	m_pLayout		 = NULL;

}

//Texture Description is not a necessary parameter for the creation of a Render Object. Therefore it is removed from 
//the parameter list of the constructor of the class RenderObj. 
HRESULT MRTRenderObject::OnD3D10CreateDevice( ID3D10Effect	*pEffect, ID3D10Device* pDev10, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
	// Though pBackBufferSurfaceDesc is passed in as a parameter, the function so far has nothing to do with it
	// Globally speaking you should create rasterize render state here
	HRESULT hr;
	
	m_pEffect = pEffect;
	
	if(  pEffect != NULL )
	{
		static const D3D10_INPUT_ELEMENT_DESC scenemeshlayout[] =
		{
			{ "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },
			{ "NORMAL", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D10_INPUT_PER_VERTEX_DATA, 0 },
			{ "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 24, D3D10_INPUT_PER_VERTEX_DATA, 0 },
		};

		D3D10_PASS_DESC PassDesc;
		
		(m_pEffect->GetTechniqueByName( m_pTechniqueName ));
		V_RETURN(m_pEffect->GetTechniqueByName( m_pTechniqueName )->GetPassByIndex(0)->GetDesc(&PassDesc));
		V_RETURN(pDev10->CreateInputLayout( scenemeshlayout, 3, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &m_pLayout ));
	}
	 

	return S_OK;

}
MRTRenderObject::~MRTRenderObject()
{
	//OnD3D10DestroyDevice();
};

// Texture must be updated here, Because the Backbuffer changed, the texture must change accordingly
HRESULT MRTRenderObject::OnD3D10SwapChainResized(	D3D10_TEXTURE2D_DESC par_Tex0desc,
													D3D10_TEXTURE2D_DESC par_Tex1desc,
													D3D10_TEXTURE2D_DESC par_Tex2desc,
													D3D10_TEXTURE2D_DESC par_Tex3desc,
													ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, 
													const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
	 // Globally you should create depth stencil view here
	 HRESULT hr;
	 {
		 //The member texDesc of the class should be updated as soon as the window size changes, otherwise
		 //the mismatch of the texture and the screen is introduced.
		 m_Tex0Desc = par_Tex0desc;

		 V(pDev10->CreateTexture2D(&m_Tex0Desc, NULL, &m_pTexture0));

		 D3D10_SHADER_RESOURCE_VIEW_DESC srViewDesc;
		 srViewDesc.Format = m_Tex0Desc.Format;
		 srViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
		 srViewDesc.Texture2D.MostDetailedMip = 0;
		 srViewDesc.Texture2D.MipLevels = 1;
		 V(pDev10->CreateShaderResourceView(m_pTexture0, &srViewDesc, &m_pSRView0));

		 D3D10_RENDER_TARGET_VIEW_DESC rtViewDesc;
		 rtViewDesc.ViewDimension = D3D10_RTV_DIMENSION_TEXTURE2D;
		 rtViewDesc.Format = m_Tex0Desc.Format;
		 rtViewDesc.Texture2D.MipSlice = 0;
		 V(pDev10->CreateRenderTargetView(m_pTexture0, &rtViewDesc, &m_pRTView0));
	 }
	 {
		 //The member texDesc of the class should be updated as soon as the window size changes, otherwise
		 //the mismatch of the texture and the screen is introduced.
		 m_Tex1Desc = par_Tex1desc;

		 V(pDev10->CreateTexture2D(&m_Tex1Desc, NULL, &m_pTexture1));

		 D3D10_SHADER_RESOURCE_VIEW_DESC srViewDesc;
		 srViewDesc.Format = m_Tex1Desc.Format;
		 srViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
		 srViewDesc.Texture2D.MostDetailedMip = 0;
		 srViewDesc.Texture2D.MipLevels = 1;
		 V(pDev10->CreateShaderResourceView(m_pTexture1, &srViewDesc, &m_pSRView1));

		 D3D10_RENDER_TARGET_VIEW_DESC rtViewDesc;
		 rtViewDesc.ViewDimension = D3D10_RTV_DIMENSION_TEXTURE2D;
		 rtViewDesc.Format = m_Tex1Desc.Format;
		 rtViewDesc.Texture2D.MipSlice = 0;
		 V(pDev10->CreateRenderTargetView(m_pTexture1, &rtViewDesc, &m_pRTView1));
	 }
	 {
		 //The member texDesc of the class should be updated as soon as the window size changes, otherwise
		 //the mismatch of the texture and the screen is introduced.
		 m_Tex2Desc = par_Tex2desc;

		 V(pDev10->CreateTexture2D(&m_Tex2Desc, NULL, &m_pTexture2));

		 D3D10_SHADER_RESOURCE_VIEW_DESC srViewDesc;
		 srViewDesc.Format = m_Tex2Desc.Format;
		 srViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
		 srViewDesc.Texture2D.MostDetailedMip = 0;
		 srViewDesc.Texture2D.MipLevels = 1;
		 V(pDev10->CreateShaderResourceView(m_pTexture2, &srViewDesc, &m_pSRView2));

		 D3D10_RENDER_TARGET_VIEW_DESC rtViewDesc;
		 rtViewDesc.ViewDimension = D3D10_RTV_DIMENSION_TEXTURE2D;
		 rtViewDesc.Format = m_Tex2Desc.Format;
		 rtViewDesc.Texture2D.MipSlice = 0;
		 V(pDev10->CreateRenderTargetView(m_pTexture2, &rtViewDesc, &m_pRTView2));
	 }
	 {
		 //The member texDesc of the class should be updated as soon as the window size changes, otherwise
		 //the mismatch of the texture and the screen is introduced.
		 m_Tex3Desc = par_Tex3desc;

		 V(pDev10->CreateTexture2D(&m_Tex3Desc, NULL, &m_pTexture3));

		 D3D10_SHADER_RESOURCE_VIEW_DESC srViewDesc;
		 srViewDesc.Format = m_Tex3Desc.Format;
		 srViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
		 srViewDesc.Texture2D.MostDetailedMip = 0;
		 srViewDesc.Texture2D.MipLevels = 1;
		 V(pDev10->CreateShaderResourceView(m_pTexture3, &srViewDesc, &m_pSRView3));

		 D3D10_RENDER_TARGET_VIEW_DESC rtViewDesc;
		 rtViewDesc.ViewDimension = D3D10_RTV_DIMENSION_TEXTURE2D;
		 rtViewDesc.Format = m_Tex3Desc.Format;
		 rtViewDesc.Texture2D.MipSlice = 0;
		 V(pDev10->CreateRenderTargetView(m_pTexture3, &rtViewDesc, &m_pRTView3));
	 }
	 return S_OK;

}

void	MRTRenderObject::OnD3D10SwapChainReleasing( void* pUserContext )
{
	 SAFE_RELEASE( m_pTexture0 );
	 SAFE_RELEASE( m_pTexture1 );
	 SAFE_RELEASE( m_pTexture2 );
	 SAFE_RELEASE( m_pTexture3 );

	 SAFE_RELEASE( m_pSRView0 );
	 SAFE_RELEASE( m_pSRView1 );
	 SAFE_RELEASE( m_pSRView2 );
	 SAFE_RELEASE( m_pSRView3 );

	 SAFE_RELEASE( m_pRTView0 );
	 SAFE_RELEASE( m_pRTView1 );
	 SAFE_RELEASE( m_pRTView2 );
	 SAFE_RELEASE( m_pRTView3 );

}


//Depth Stencil View are passed in as a parameter of the OnFrameRender member function. This is also a 
//consideration of performance, but bring the limitation that

void	MRTRenderObject::OnD3D10FrameRender(   ID3D10Effect *m_pEffect,
											   ID3D10EffectTechnique *pSuitKernelTech,
											   ID3D10EffectTechnique *pBodyKernelTech,
											   ID3D10EffectTechnique *pSceneKernelTech,
											   D3DXMATRIX *pWorldViewProj,
											   S3UTMesh *MeshScene, 
											   ID3D10DepthStencilView *pDSV, 
											   ID3D10Device* pDev10, 
											   double fTime, float fElapsedTime, void* pUserContext, float r,float g,float b,float a )
{

	//Render Objects to RTs of the same size. If you intend to render different sized RTs special cares must be taken.
	 
	 m_Viewport.Height = m_Tex0Desc.Height;
	 m_Viewport.Width  = m_Tex0Desc.Width;
	
	 m_Viewport.MinDepth = 0;
     m_Viewport.MaxDepth = 1;
     m_Viewport.TopLeftX = 0;
     m_Viewport.TopLeftY = 0;

	 pDev10->RSSetViewports(1, &m_Viewport);
 
	 //Though these clear incurs a lot of performance hit
	 //we still need them, otherwise, the geometry info of prev frame remains on those part untouched in the current frame.

	 float ClearColor[4] = { 0, 0, 0, 1 };
     pDev10->ClearRenderTargetView(m_pRTView0, ClearColor);
     pDev10->ClearRenderTargetView(m_pRTView1, ClearColor);
     pDev10->ClearRenderTargetView(m_pRTView2, ClearColor);
     pDev10->ClearRenderTargetView(m_pRTView3, ClearColor);
 
	 pDev10->IASetInputLayout( m_pLayout );
	 ID3D10EffectTechnique *pTechnique = m_pEffect->GetTechniqueByName( m_pTechniqueName );

	 //Render Targets are set but not restored for efficiency. Be careful to restore them!
     ID3D10DepthStencilView* pOrigDSV = DXUTGetD3D10DepthStencilView();
     ID3D10RenderTargetView* pOrigRTV = DXUTGetD3D10RenderTargetView();

     ID3D10RenderTargetView* aRTViews[ NUM_RT ] = { m_pRTView0,m_pRTView1,m_pRTView2,m_pRTView3 };

	 pDev10->OMSetRenderTargets(NUM_RT, aRTViews, pDSV);
     ID3D10EffectShaderResourceVariable *pTexture = NULL;//m_pEffect->GetVariableByName("DiffuseTex")->AsShaderResource();
	 
	 MeshScene->Render( MAX_BONE_MATRICES,
						(FLOAT)SCALE,
						m_pEffect,
						pSuitKernelTech,
						pBodyKernelTech,
						pSceneKernelTech,
						pSceneKernelTech,
						pWorldViewProj,
						pDev10,
						fTime,fElapsedTime,pUserContext );

	 pDev10->OMSetRenderTargets(1, &pOrigRTV, pOrigDSV);
#ifdef B_DO_DUMP
	 DumpFrameResult( m_pTexture0,L"e:\\TexPosInWorld.dds",pDev10 );
	 DumpFrameResult( m_pTexture1,L"e:\\TexNormalInWorld.dds",pDev10 );
#endif

}

void	MRTRenderObject::OnD3D10DestroyDevice( void* pUserContext )
{
	OnD3D10SwapChainReleasing(NULL);

	SAFE_RELEASE( m_pLayout );
}

void	MRTRenderObject::DumpFrameResult( ID3D10Texture2D *pSrcTex,WCHAR *FileName,ID3D10Device* pDev10 )
{
	HRESULT hr;
	{
		ID3D10Texture2D *pTex = NULL;
		D3D10_TEXTURE2D_DESC textureDesc;
		pSrcTex->GetDesc(&textureDesc);
		textureDesc.CPUAccessFlags = D3D10_CPU_ACCESS_READ;
		textureDesc.Usage = D3D10_USAGE_STAGING;
		textureDesc.BindFlags = 0;
		V(pDev10->CreateTexture2D(&textureDesc, NULL, &pTex));
		pDev10->CopyResource(pTex, pSrcTex);
	    
		D3DX10SaveTextureToFile(pTex, D3DX10_IFF_DDS, FileName);

		SAFE_RELEASE( pTex );
	}

}
#endif