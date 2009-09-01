// I'm not that trust Dynamic Branch, therefore I choose to use pre-rendered depth buffer to reject pixels that should not be rendered. Although outputting depth
// would not benefit from z rejection optimization, for simple scenes it might still worth doing so.
// I plan to experiment both methods ( dynamic branch and z rejection )


#ifndef DO
#define DO

#include <dxut.h>
#include <dxutgui.h>
#include <dxutsettingsdlg.h>
#include <sdkmisc.h>

#include <S3UTmesh.h>

class DepthObject{
public:

	DepthObject( char *TechName );
	~DepthObject(){};

	HRESULT OnD3D10CreateDevice( ID3D10Effect	*pEffect, ID3D10Device* pDev10, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
	HRESULT OnD3D10SwapChainResized( D3D10_TEXTURE2D_DESC desc, ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
	void	OnD3D10FrameRender( S3UTMesh *MeshScene, ID3D10Device* pDev10, double fTime, float fElapsedTime, void* pUserContext );
	void	OnD3D10SwapChainReleasing( void* pUserContext );
	void	OnD3D10DestroyDevice( void* pUserContext );
	void	DumpFrameResult( WCHAR *FileName,ID3D10Device* pDev10  );
	void	Clear(ID3D10Device* pDev10);

	ID3D10Texture2D				*m_pTexture;
	D3D10_TEXTURE2D_DESC		 m_TexDesc;

	ID3D10DepthStencilView		*m_pDSView;
	ID3D10ShaderResourceView	*m_pSRView;
	ID3D10InputLayout			*m_pLayout;
	ID3D10Effect				*m_pEffect;
	char						*m_pTechniqueName;
	D3D10_VIEWPORT				 m_Viewport;

};

DepthObject::DepthObject( char *TechName )
{
	m_pTechniqueName = TechName;
	m_pEffect		 = NULL;
	m_pTexture		 = NULL;
	m_pDSView		 = NULL;
	m_pLayout		 = NULL;
}

HRESULT DepthObject::OnD3D10CreateDevice( ID3D10Effect	*pEffect, ID3D10Device* pDev10, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
	// Though pBackBufferSurfaceDesc is passed in as a parameter, the function so far has nothing to do with it
	// Globally speaking you should create rasterize render state here
	HRESULT hr;
	
	m_pEffect = pEffect;
	
	static const D3D10_INPUT_ELEMENT_DESC scenemeshlayout[] =
    {
        { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },
        { "NORMAL", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12, D3D10_INPUT_PER_VERTEX_DATA, 0 },
        { "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT, 0, 24, D3D10_INPUT_PER_VERTEX_DATA, 0 },
    };

	D3D10_PASS_DESC PassDesc;
	
	V_RETURN(m_pEffect->GetTechniqueByName( m_pTechniqueName )->GetPassByIndex(0)->GetDesc(&PassDesc));
	V_RETURN(pDev10->CreateInputLayout( scenemeshlayout, 3, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &m_pLayout ));

	 

	return S_OK;

}

// Texture must be updated here, Because the Backbuffer changed, the texture must change accordingly
HRESULT DepthObject::OnD3D10SwapChainResized( D3D10_TEXTURE2D_DESC desc, ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
	 // Globally you should create depth stencil view here
	 HRESULT hr;

	 m_TexDesc = desc;

	 V(pDev10->CreateTexture2D(&m_TexDesc, NULL, &m_pTexture));
        
	 D3D10_DEPTH_STENCIL_VIEW_DESC dsViewDesc;
     dsViewDesc.Format = DXGI_FORMAT_D32_FLOAT;
     dsViewDesc.ViewDimension = D3D10_DSV_DIMENSION_TEXTURE2D;
     dsViewDesc.Texture2D.MipSlice = 0;
     V(pDev10->CreateDepthStencilView(m_pTexture, &dsViewDesc, &m_pDSView));

	 if( m_TexDesc.Format == DXGI_FORMAT_R32_TYPELESS ){	 
		 D3D10_SHADER_RESOURCE_VIEW_DESC srViewDesc;
		 srViewDesc.Format = DXGI_FORMAT_R32_FLOAT;
		 srViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
		 srViewDesc.Texture2D.MostDetailedMip = 0;
		 srViewDesc.Texture2D.MipLevels = 1;
		 V(pDev10->CreateShaderResourceView(m_pTexture, &srViewDesc, &m_pSRView));
	 }


	 return S_OK;

}

void	DepthObject::OnD3D10SwapChainReleasing( void* pUserContext )
{
	 SAFE_RELEASE( m_pTexture );
	 SAFE_RELEASE( m_pDSView );
	 if( m_TexDesc.Format == DXGI_FORMAT_R32_TYPELESS ){	
		SAFE_RELEASE( m_pSRView );
	 }



}

void	DepthObject::OnD3D10FrameRender( S3UTMesh *MeshScene, ID3D10Device* pDev10, double fTime, float fElapsedTime, void* pUserContext )
{
	 
	 m_Viewport.Height = m_TexDesc.Height;
	 m_Viewport.Width  = m_TexDesc.Width;
	
	 m_Viewport.MinDepth = 0;
     m_Viewport.MaxDepth = 1;
     m_Viewport.TopLeftX = 0;
     m_Viewport.TopLeftY = 0;

	 pDev10->RSSetViewports(1, &m_Viewport);
 
	
     pDev10->ClearDepthStencilView( m_pDSView, D3D10_CLEAR_DEPTH, 1.0, 0);
 
	 pDev10->IASetInputLayout( m_pLayout );
	 ID3D10EffectTechnique *pTechnique = m_pEffect->GetTechniqueByName( m_pTechniqueName );

	 ID3D10RenderTargetView *pNullRTView = NULL;
	 pDev10->OMSetRenderTargets(1, &pNullRTView, m_pDSView);
     ID3D10EffectShaderResourceVariable *pTexture = m_pEffect->GetVariableByName("DiffuseTex")->AsShaderResource();
	 
	 MeshScene->Render(pDev10, pTechnique,pTexture);

}

void	DepthObject::Clear(ID3D10Device* pDev10)
{
     pDev10->ClearDepthStencilView( m_pDSView, D3D10_CLEAR_DEPTH, 1.0, 0);
}

void	DepthObject::OnD3D10DestroyDevice( void* pUserContext )
{
	SAFE_RELEASE( m_pLayout );
}

void	DepthObject::DumpFrameResult( WCHAR *FileName,ID3D10Device* pDev10 )
{
	/*
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
	*/
}
#endif