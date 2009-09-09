//-------------------------------------------------------------------------
//File:   FullRTQuadRender.cpp
//Author: Baoguang Yang
//
//Copyright (c) 2009 S3Graphics Corporation. All rights reserved.
//
//This renders a full screen quad.
//-------------------------------------------------------------------------

#ifndef FULL_SCR_RENDER
#define FULL_SCR_RENDER

#include <dxut.h>
#include <dxutgui.h>
#include <dxutsettingsdlg.h>
#include <sdkmisc.h>

#include <S3UTmesh.h>
#include "CommonDef.h"

struct SCREEN_VERTEX
{
    D3DXVECTOR4 pos;
    D3DXVECTOR4 tex;

    static const DWORD FVF;
};

class FullRTQuadRender{
public:

	FullRTQuadRender( char *TechName );

	HRESULT OnD3D10CreateDevice( ID3D10Effect	*par_pEffect, ID3D10Device* par_pDev10, 
								 const DXGI_SURFACE_DESC* par_pBackBufferSurfaceDesc, void* pUserContext );

	HRESULT OnD3D10SwapChainResized( D3D10_TEXTURE2D_DESC desc, ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
	
	void DrawFullScreenQuad( ID3D10Device* par_pDev10, ID3D10EffectTechnique* par_pTech, UINT par_RTWidth, UINT par_RTHeight );
	
	void OnD3D10FrameRender(  ID3D10Effect *par_pEffect,
							  ID3D10EffectTechnique *par_pTech,
							  ID3D10Device* par_pDev10, 
							  double fTime, float fElapsedTime, void* pUserContext );
	
	void	OnD3D10SwapChainReleasing( void* pUserContext );
	void	OnD3D10DestroyDevice( void* pUserContext = NULL );
	void	DumpFrameResult( WCHAR *FileName,ID3D10Device* pDev10  );
	void	SetUseMyRT( bool par_bUseMyRT ) { m_bUseMyRT = par_bUseMyRT; }
	~FullRTQuadRender();


	ID3D10Buffer				*m_pScreenQuadVB;
	ID3D10Texture2D				*m_pTexture;
	D3D10_TEXTURE2D_DESC		 m_TexDesc;

	ID3D10RenderTargetView		*m_pRTView;
	ID3D10ShaderResourceView	*m_pSRView;
	ID3D10InputLayout			*m_pQuadLayout;
	ID3D10Effect				*m_pEffect;
	char						*m_pTechniqueName;
	D3D10_VIEWPORT				 m_Viewport;
	bool						 m_bUseMyRT;

};

FullRTQuadRender::FullRTQuadRender( char *TechName )
{
	m_pTechniqueName = TechName;
	m_pEffect		 = NULL;
	m_pTexture		 = NULL;
	m_pRTView		 = NULL;
	m_pSRView		 = NULL;
	m_pQuadLayout	 = NULL;
	m_bUseMyRT	     = true;
}
FullRTQuadRender::~FullRTQuadRender()
{
	//OnD3D10DestroyDevice();
}
//Texture Description is not a necessary parameter for the creation of a Render Object. Therefore it is removed from 
//the parameter list of the constructor of the class RenderObj. 
HRESULT FullRTQuadRender::OnD3D10CreateDevice( ID3D10Effect	*par_pEffect, ID3D10Device* par_pDev10, 
										       const DXGI_SURFACE_DESC* par_pBackBufferSurfaceDesc, void* pUserContext )
{
	// Though pBackBufferSurfaceDesc is passed in as a parameter, the function so far has nothing to do with it
	// Globally speaking you should create rasterize render state here
	HRESULT hr;
	
	m_pEffect = par_pEffect;
	
	if(  par_pEffect != NULL )
	{
		// Create our quad input layout
		const D3D10_INPUT_ELEMENT_DESC quadlayout[] =
		{
			{ "POSITION", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },
			{ "TEXCOORD", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 16, D3D10_INPUT_PER_VERTEX_DATA, 0 },
		};

		D3D10_PASS_DESC PassDesc;
		
		(m_pEffect->GetTechniqueByName( m_pTechniqueName ));
		V_RETURN(m_pEffect->GetTechniqueByName( m_pTechniqueName )->GetPassByIndex(0)->GetDesc(&PassDesc));
		V_RETURN(par_pDev10->CreateInputLayout( quadlayout, 2, PassDesc.pIAInputSignature, 
												PassDesc.IAInputSignatureSize, &m_pQuadLayout ));
	}

    // Create a screen quad for all render to texture operations
    SCREEN_VERTEX svQuad[4];
    svQuad[0].pos = D3DXVECTOR4( -1.0f, 1.0f, 0.5f, 1.0f );
    svQuad[0].tex = D3DXVECTOR4( 0.0f, 0.0f, 0.0f, 0.0f );
    svQuad[1].pos = D3DXVECTOR4( 1.0f, 1.0f, 0.5f, 1.0f );
    svQuad[1].tex = D3DXVECTOR4( 1.0f, 0.0f, 0.0f, 0.0f );
    svQuad[2].pos = D3DXVECTOR4( -1.0f, -1.0f, 0.5f, 1.0f );
    svQuad[2].tex = D3DXVECTOR4( 0.0f, 1.0f, 0.0f, 0.0f );
    svQuad[3].pos = D3DXVECTOR4( 1.0f, -1.0f, 0.5f, 1.0f );
    svQuad[3].tex = D3DXVECTOR4( 1.0f, 1.0f, 0.0f, 0.0f );


    D3D10_BUFFER_DESC vbdesc =
    {
        4 * sizeof( SCREEN_VERTEX ),
        D3D10_USAGE_DEFAULT,
        D3D10_BIND_VERTEX_BUFFER,
        0,
        0
    };

    D3D10_SUBRESOURCE_DATA InitData;
    InitData.pSysMem = svQuad;
    InitData.SysMemPitch = 0;
    InitData.SysMemSlicePitch = 0;
    V_RETURN( par_pDev10->CreateBuffer( &vbdesc, &InitData, &m_pScreenQuadVB ) );

	return S_OK;

}

// Texture must be updated here, Because the Backbuffer changed, the texture must change accordingly
HRESULT FullRTQuadRender::OnD3D10SwapChainResized( D3D10_TEXTURE2D_DESC desc, ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
	 // Globally you should create depth stencil view here
	 HRESULT hr;

	 //The member texDesc of the class should be updated as soon as the window size changes, otherwise
	 //the mismatch of the texture and the screen is introduced.
	 m_TexDesc = desc;

	 V(pDev10->CreateTexture2D(&m_TexDesc, NULL, &m_pTexture));

	 D3D10_SHADER_RESOURCE_VIEW_DESC srViewDesc;
	 srViewDesc.Format = m_TexDesc.Format;
	 srViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
	 srViewDesc.Texture2D.MostDetailedMip = 0;
	 srViewDesc.Texture2D.MipLevels = 1;
	 V(pDev10->CreateShaderResourceView(m_pTexture, &srViewDesc, &m_pSRView));

	 D3D10_RENDER_TARGET_VIEW_DESC rtViewDesc;
	 rtViewDesc.ViewDimension = D3D10_RTV_DIMENSION_TEXTURE2D;
	 rtViewDesc.Format = m_TexDesc.Format;
	 rtViewDesc.Texture2D.MipSlice = 0;
	 V(pDev10->CreateRenderTargetView(m_pTexture, &rtViewDesc, &m_pRTView));

	 return S_OK;

}

void FullRTQuadRender::OnD3D10SwapChainReleasing( void* pUserContext )
{
	 SAFE_RELEASE( m_pTexture );
	 SAFE_RELEASE( m_pSRView );
	 SAFE_RELEASE( m_pRTView );
}

void FullRTQuadRender::DrawFullScreenQuad( ID3D10Device* par_pDev10, ID3D10EffectTechnique* par_pTech, 
										  UINT par_RTWidth, UINT par_RTHeight )
{
    // Save the Old viewport
    D3D10_VIEWPORT vpOld[D3D10_VIEWPORT_AND_SCISSORRECT_MAX_INDEX];
    UINT nViewPorts = 1;
    par_pDev10->RSGetViewports( &nViewPorts, vpOld );

    // Setup the viewport to match the backbuffer
    D3D10_VIEWPORT vp;
    vp.Width = par_RTWidth;
    vp.Height = par_RTHeight;
    vp.MinDepth = 0.0f;
    vp.MaxDepth = 1.0f;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;
    par_pDev10->RSSetViewports( 1, &vp );


    UINT strides = sizeof( SCREEN_VERTEX );
    UINT offsets = 0;
    ID3D10Buffer* pBuffers[1] = { m_pScreenQuadVB };

    par_pDev10->IASetInputLayout( m_pQuadLayout );
    par_pDev10->IASetVertexBuffers( 0, 1, pBuffers, &strides, &offsets );
    par_pDev10->IASetPrimitiveTopology( D3D10_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP );

    D3D10_TECHNIQUE_DESC techDesc;
    par_pTech->GetDesc( &techDesc );

    for( UINT uiPass = 0; uiPass < techDesc.Passes; uiPass++ )
    {
        par_pTech->GetPassByIndex( uiPass )->Apply( 0 );

        par_pDev10->Draw( 4, 0 );
    }

    // Restore the Old viewport
    par_pDev10->RSSetViewports( nViewPorts, vpOld );
}



//Depth Stencil View are passed in as a parameter of the OnFrameRender member function. This is also a 
//consideration of performance, but bring the limitation that
void FullRTQuadRender::OnD3D10FrameRender(  ID3D10Effect *par_pEffect,
											ID3D10EffectTechnique *par_pTech,
											ID3D10Device* par_pDev10, 
											double fTime, float fElapsedTime, void* pUserContext )
{

 	 //Render Objects to RTs of the same size. If you intend to render different sized RTs special cares must be taken. 
	 float ClearColor[4] = { 1, 1, 1, 1 };
     par_pDev10->ClearRenderTargetView(m_pRTView, ClearColor);

	 par_pDev10->IASetInputLayout( m_pQuadLayout );

	 //m_pTechniqueName is used only for creating input layout
	 //however, par_pTech and m_pTechniqueName are prone to mistakenly usage
	 //so I force them to be the same.
	 assert( par_pTech == par_pEffect->GetTechniqueByName( m_pTechniqueName ) );
	 ID3D10EffectTechnique *pTech = par_pTech;

	 //Render Targets are set but not restored for efficiency. Be careful to restore them!
     ID3D10DepthStencilView* pOrigDSV = DXUTGetD3D10DepthStencilView();
     ID3D10RenderTargetView* pOrigRTV = DXUTGetD3D10RenderTargetView();

	 if( m_bUseMyRT )
	 {
		 par_pDev10->OMSetRenderTargets(1, &m_pRTView, NULL);//Quad Render requires no depth stencil surface
	 }
     ID3D10EffectShaderResourceVariable *pTexture = NULL;//m_pEffect->GetVariableByName("DiffuseTex")->AsShaderResource();
  
	 DrawFullScreenQuad( par_pDev10, pTech, m_TexDesc.Width, m_TexDesc.Height );

	 par_pDev10->OMSetRenderTargets(1, &pOrigRTV, pOrigDSV);

}

void FullRTQuadRender::OnD3D10DestroyDevice( void* pUserContext )
{
	OnD3D10SwapChainReleasing(pUserContext);
	SAFE_RELEASE( m_pQuadLayout );
	SAFE_RELEASE( m_pScreenQuadVB );
}

void FullRTQuadRender::DumpFrameResult( WCHAR *FileName,ID3D10Device* pDev10 )
{
	HRESULT hr;
	
	ID3D10Texture2D *pTex = NULL;
    D3D10_TEXTURE2D_DESC textureDesc;
    m_pTexture->GetDesc(&textureDesc);
	textureDesc.Format = m_TexDesc.Format;
    textureDesc.CPUAccessFlags = D3D10_CPU_ACCESS_READ;
    textureDesc.Usage = D3D10_USAGE_STAGING;
    textureDesc.BindFlags = 0;
    V(pDev10->CreateTexture2D(&textureDesc, NULL, &pTex));
    pDev10->CopyResource(pTex, m_pTexture);
    
	D3DX10SaveTextureToFile(pTex, D3DX10_IFF_DDS, FileName);

	SAFE_RELEASE( pTex );

}
#endif