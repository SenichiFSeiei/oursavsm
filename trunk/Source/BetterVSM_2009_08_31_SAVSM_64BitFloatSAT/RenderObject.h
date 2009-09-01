// In this framework, render state are set outside the RenderObject due to consideration on Hardware Performance
// Depth Stencil View are passed in as a parameter of the OnFrameRender member function. This is also a consideration of performance, but bring the limitation that
// Render Objects render to RTs of the same size. If you intend to render different RTs special cares must be taken.
// Render Targets are set but not restored for efficiency. Be careful to restore them!

//About how to be efficient: 1) Memory Efficiency: create textures needed only. 2) Time Efficiency: draw passes needed
//only. 1) could be done in function SwapChainResized and SwapChainReleasing because textures are created and destoried 
//in these two functions. 2) could be done in function FrameRender.

//I found that RenderObject and DepthObject can be freely created cause that such creations do not incur  texture creation
//therefore do not affect memory efficiency. Only the function SwapChainResized and SwapChainReleasing should be controlled
//for efficiencies.


#ifndef RO
#define RO

#include <dxut.h>
#include <dxutgui.h>
#include <dxutsettingsdlg.h>
#include <sdkmisc.h>

#include <S3UTmesh.h>
#include "CommonDef.h"

class RenderObject{
public:

	RenderObject( char *TechName );
	~RenderObject(){};

	HRESULT OnD3D10CreateDevice( ID3D10Effect	*pEffect, ID3D10Device* pDev10, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
	HRESULT OnD3D10SwapChainResized( D3D10_TEXTURE2D_DESC desc, ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
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
	void	OnD3D10DestroyDevice( void* pUserContext );
	void	DumpFrameResult( WCHAR *FileName,ID3D10Device* pDev10  );

	ID3D10Texture2D				*m_pTexture;
	D3D10_TEXTURE2D_DESC		 m_TexDesc;

	ID3D10RenderTargetView		*m_pRTView;
	ID3D10ShaderResourceView	*m_pSRView;
	ID3D10InputLayout			*m_pLayout;
	ID3D10Effect				*m_pEffect;
	char						*m_pTechniqueName;
	D3D10_VIEWPORT				 m_Viewport;

};

RenderObject::RenderObject( char *TechName )
{
	m_pTechniqueName = TechName;
	m_pEffect		 = NULL;
	m_pTexture		 = NULL;
	m_pRTView		 = NULL;
	m_pSRView		 = NULL;
	m_pLayout		 = NULL;




}

//Texture Description is not a necessary parameter for the creation of a Render Object. Therefore it is removed from 
//the parameter list of the constructor of the class RenderObj. 
HRESULT RenderObject::OnD3D10CreateDevice( ID3D10Effect	*pEffect, ID3D10Device* pDev10, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
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

// Texture must be updated here, Because the Backbuffer changed, the texture must change accordingly
HRESULT RenderObject::OnD3D10SwapChainResized( D3D10_TEXTURE2D_DESC desc, ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
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

void	RenderObject::OnD3D10SwapChainReleasing( void* pUserContext )
{
	 SAFE_RELEASE( m_pTexture );
	 SAFE_RELEASE( m_pSRView );
	 SAFE_RELEASE( m_pRTView );

}


//Depth Stencil View are passed in as a parameter of the OnFrameRender member function. This is also a 
//consideration of performance, but bring the limitation that

void	RenderObject::OnD3D10FrameRender(   ID3D10Effect *m_pEffect,
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
	 
	 m_Viewport.Height = m_TexDesc.Height;
	 m_Viewport.Width  = m_TexDesc.Width;
	
	 m_Viewport.MinDepth = 0;
     m_Viewport.MaxDepth = 1;
     m_Viewport.TopLeftX = 0;
     m_Viewport.TopLeftY = 0;

	 pDev10->RSSetViewports(1, &m_Viewport);
 
	
	 float ClearColor[4] = { r, g, b, a };
     pDev10->ClearRenderTargetView(m_pRTView, ClearColor);
 
	 pDev10->IASetInputLayout( m_pLayout );
	 ID3D10EffectTechnique *pTechnique = m_pEffect->GetTechniqueByName( m_pTechniqueName );

	 //Render Targets are set but not restored for efficiency. Be careful to restore them!
     ID3D10DepthStencilView* pOrigDSV = DXUTGetD3D10DepthStencilView();
     ID3D10RenderTargetView* pOrigRTV = DXUTGetD3D10RenderTargetView();


	 pDev10->OMSetRenderTargets(1, &m_pRTView, pDSV);
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

}

void	RenderObject::OnD3D10DestroyDevice( void* pUserContext )
{
	SAFE_RELEASE( m_pLayout );
}

void	RenderObject::DumpFrameResult( WCHAR *FileName,ID3D10Device* pDev10 )
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