#ifndef RENDER_FINAL
#define RENDER_FINAL

#include "CommonDef.h"
#include "SoftShadowMap.h"
#include "BasicSSMAlgorithm.h"
#include "RenderObject.h"
#include "DepthObject.h"
#include "OGRE_LAYOUT.h"
#include "InputBuffer.h"
#include "FullRTQuadRender.h"


class RenderFinal:public BasicSSMAlgorithm
{
public:
	ID3D10Effect *m_pEffect;

	FullRTQuadRender *m_pScrQuadRender;

	RenderFinal();
	HRESULT OnD3D10CreateDevice(ID3D10Device* pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void* pUserContext);
	void OnD3D10FrameRender(CDXUTDialog &g_SampleUI,S3UTMesh &g_MeshScene,float g_fFilterSize,SSMap &ssmap,
							S3UTCamera &g_CameraRef,S3UTCamera &g_LCameraRef,
							ID3D10Device* pDev10, double fTime, float fElapsedTime, void* pUserContext);
	void OnD3D10DestroyDevice( void* pUserContext = NULL);
	HRESULT OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
	void	OnD3D10SwapChainReleasing( void* pUserContext );
	HRESULT CreateShader(ID3D10Device *pDev10);
	
	~RenderFinal();

	InputBuffer *m_pGBuffer;
	bool m_bShaderChanged;
};

RenderFinal::RenderFinal()
{
	m_pEffect = NULL;
	m_pScrQuadRender = new FullRTQuadRender("FinalPresentPass");
	m_bShaderChanged = false;
}

RenderFinal::~RenderFinal()
{
	//OnD3D10DestroyDevice();
}

HRESULT RenderFinal::CreateShader(ID3D10Device *pDev10)
{
	HRESULT hr;
	
	WCHAR str[MAX_PATH];
    V_RETURN(DXUTFindDXSDKMediaFileCch(str, MAX_PATH, (RENDER_FINAL_FILE_NAME) ));
    ID3D10Blob *pErrors;
    if (D3DX10CreateEffectFromFile(str, NULL, NULL, "fx_4_0", D3D10_SHADER_DEBUG|D3D10_SHADER_SKIP_OPTIMIZATION, 0, pDev10, NULL, NULL, &m_pEffect, &pErrors, &hr) != S_OK)
    {
        MessageBoxA(NULL, (char *)pErrors->GetBufferPointer(), "Compilation error", MB_OK);
        exit(0);
    }	
	return S_OK;

}

HRESULT RenderFinal::OnD3D10CreateDevice(ID3D10Device *pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void *pUserContext)
{

	CreateShader( pDev10 );
	m_pScrQuadRender->OnD3D10CreateDevice(m_pEffect,pDev10,pBackBufferSurfaceDesc,pUserContext);

	return S_OK;

}
void	RenderFinal::OnD3D10SwapChainReleasing( void* pUserContext )
{
	m_pScrQuadRender->OnD3D10SwapChainReleasing(pUserContext);
}

HRESULT RenderFinal::OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
	D3D10_TEXTURE2D_DESC rtDesc_scrpos =
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
	m_pScrQuadRender->OnD3D10SwapChainResized(rtDesc_scrpos,pDev10,pSwapChain,pBackBufferSurfaceDesc,pUserContext);

	return S_OK;
}

void RenderFinal::OnD3D10FrameRender(CDXUTDialog &g_SampleUI,S3UTMesh &g_MeshScene,float g_fFilterSize,
									  SSMap &ssmap,S3UTCamera &g_CameraRef,S3UTCamera &g_LCameraRef, 
									  ID3D10Device* pDev10, double fTime, float fElapsedTime, void* pUserContext)
{
	if( m_bShaderChanged )
	{
		CreateShader(pDev10);
		m_bShaderChanged = false;
	}

	HRESULT hr;
    D3DXMATRIX mTmp, mWorldView, mWorldViewProj, mWorldViewInv;
    D3DXMatrixInverse(&mTmp, NULL, g_CameraRef.GetWorldMatrix());
    D3DXMatrixMultiply(&mWorldView, &mTmp, g_CameraRef.GetViewMatrix());

    D3DXMatrixMultiply(&mWorldViewProj, &mWorldView, g_CameraRef.GetProjMatrix());
    
	pDev10->OMSetRenderTargets(1,&m_pRTV,DXUTGetD3D10DepthStencilView());
	pDev10->ClearDepthStencilView(DXUTGetD3D10DepthStencilView(), D3D10_CLEAR_DEPTH, 1.0, 0);
	V(m_pEffect->GetVariableByName("TexFinalResult")->AsShaderResource()->SetResource( m_pPreResult ));
	V(m_pEffect->GetVariableByName("TexPosInWorld")->AsShaderResource()->SetResource( m_pInputBuffer->m_pInputAttributes->m_pSRView0));


	m_pScrQuadRender->SetUseMyRT( false );
	m_pScrQuadRender->OnD3D10FrameRender( m_pEffect,m_pEffect->GetTechniqueByName("FinalPresentPass"),
		                                  pDev10,fTime,fElapsedTime,pUserContext);

}

void RenderFinal::OnD3D10DestroyDevice( void* pUserContext )
{
	OnD3D10SwapChainReleasing(NULL);

    SAFE_RELEASE(m_pEffect);
	m_pScrQuadRender->OnD3D10DestroyDevice( pUserContext );
	SAFE_DELETE(m_pScrQuadRender);
}


#endif