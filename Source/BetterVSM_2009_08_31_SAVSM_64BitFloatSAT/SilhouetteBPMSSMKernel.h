#pragma once

#include "CommonDef.h"
#include "SoftShadowMap.h"
#include "BasicSSMAlgorithm.h"
#include "RenderObject.h"
#include "DepthObject.h"
#include "OGRE_LAYOUT.h"
#include "FullRTQuadRender.h"


class SilhouetteBPMSSMKernel:public BasicSSMAlgorithm
{
public:
	ID3D10Effect *m_pEffect;
	ID3D10InputLayout *m_pMaxLayout;
	ID3D10ShaderResourceView*           m_pAreaTextureRV;
	FullRTQuadRender *m_pHSMKernel;
	FullRTQuadRender *m_pShadowResult;

	SilhouetteBPMSSMKernel();
	HRESULT OnD3D10CreateDevice(ID3D10Device* pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void* pUserContext);
	void OnD3D10FrameRender(bool render_ogre, 
							bool render_scene, 
							CDXUTDialog &g_SampleUI,
							S3UTMesh &g_MeshScene,
							float g_fFilterSize,
							SSMap &ssmap,
							S3UTCamera &g_CameraRef,
							S3UTCamera &g_LCameraRef,
							ID3D10Device* pDev10, 
							double fTime, 
							float fElapsedTime, 
							void* pUserContext);
	void OnD3D10DestroyDevice();
	HRESULT OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
	void	OnD3D10SwapChainReleasing( void* pUserContext );
	
	~SilhouetteBPMSSMKernel();



};

SilhouetteBPMSSMKernel::SilhouetteBPMSSMKernel()
{
	m_pEffect = NULL;
	m_pMaxLayout = NULL;
	m_pAreaTextureRV = NULL;
	m_pHSMKernel = NULL;
	m_pShadowResult = NULL;
}
SilhouetteBPMSSMKernel::~SilhouetteBPMSSMKernel()
{
	//OnD3D10DestroyDevice();
}
HRESULT SilhouetteBPMSSMKernel::OnD3D10CreateDevice(ID3D10Device *pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void *pUserContext)
{
	HRESULT hr;

	//Effect Creation
    WCHAR str[MAX_PATH];
    V_RETURN(DXUTFindDXSDKMediaFileCch(str, MAX_PATH, (SILHOUETTE_BP_EFFECT_FILE_NAME) ));
    ID3D10Blob *pErrors;
    if (D3DX10CreateEffectFromFile(str, NULL, NULL, "fx_4_0", D3D10_SHADER_DEBUG|D3D10_SHADER_SKIP_OPTIMIZATION, 0, pDev10, NULL, NULL, &m_pEffect, &pErrors, &hr) != S_OK)
    {
        MessageBoxA(NULL, (char *)pErrors->GetBufferPointer(), "Compilation error", MB_OK);
        exit(0);
    }

	//load texture for occluded area computation
	hr = D3DX10CreateShaderResourceViewFromFile( pDev10, L"areaT.dds", NULL, NULL, &m_pAreaTextureRV, NULL );
    if( FAILED(hr) )
        return hr;
		
	m_pHSMKernel = new FullRTQuadRender("RenderHSMKernel");
	m_pHSMKernel->OnD3D10CreateDevice(m_pEffect,pDev10,pBackBufferSurfaceDesc,pUserContext);
	
	m_pShadowResult = new FullRTQuadRender("SSMBackprojection");
	m_pShadowResult->OnD3D10CreateDevice(m_pEffect,pDev10,pBackBufferSurfaceDesc,pUserContext);
	
	return S_OK;

}
void	SilhouetteBPMSSMKernel::OnD3D10SwapChainReleasing( void* pUserContext )
{
	m_pHSMKernel->OnD3D10SwapChainReleasing(pUserContext);
	m_pShadowResult->OnD3D10SwapChainReleasing(pUserContext);
}

HRESULT SilhouetteBPMSSMKernel::OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
	D3D10_TEXTURE2D_DESC rtDesc_scrpos =
	{
		pBackBufferSurfaceDesc->Width, //UINT Width;
		pBackBufferSurfaceDesc->Height, //UINT Height;
		1,//UINT MipLevels;
		1,//UINT ArraySize;
		DXGI_FORMAT_R16G16B16A16_FLOAT,//DXGI_FORMAT Format;
		{1, 0}, //DXGI_SAMPLE_DESC SampleDesc;
		D3D10_USAGE_DEFAULT, //D3D10_USAGE Usage;

		D3D10_BIND_SHADER_RESOURCE | D3D10_BIND_RENDER_TARGET ,//UINT BindFlags;
		0,//UINT CPUAccessFlags;
		0,//UINT MiscFlags;
	};

	//only position need 32 bit floating point, 16bit is enouth for others. save memory/traffic.
	m_pHSMKernel->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	m_pShadowResult->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);

	return S_OK;
}

void SilhouetteBPMSSMKernel::OnD3D10FrameRender(bool render_ogre, 
											  bool render_scene, 
											  CDXUTDialog &g_SampleUI,
											  S3UTMesh &g_MeshScene,
											  float g_fFilterSize,
											  SSMap &ssmap,
											  S3UTCamera &g_CameraRef,
											  S3UTCamera &g_LCameraRef, 
											  ID3D10Device* pDev10, 
											  double fTime, 
											  float fElapsedTime, 
											  void* pUserContext
											  )
{
	HRESULT hr;
    D3DXMATRIX mTmp, mWorldView, mWorldViewProj, mWorldViewInv;
    D3DXMatrixInverse(&mTmp, NULL, g_CameraRef.GetWorldMatrix());
    D3DXMatrixMultiply(&mWorldView, &mTmp, g_CameraRef.GetViewMatrix());

    D3DXMatrixMultiply(&mWorldViewProj, &mWorldView, g_CameraRef.GetProjMatrix());
    D3DXMatrixInverse(&mWorldViewInv, NULL, &mWorldView);


	D3DXMATRIX mLightView;
    // here we compute light viewprojection so that light oversees the whole scene
    D3DXMATRIX mTranslate;

	D3DXMatrixInverse(&mTranslate, NULL, g_LCameraRef.GetWorldMatrix());
	D3DXMatrixMultiply(&mLightView, &mTranslate, g_LCameraRef.GetViewMatrix());

	D3DXMatrixMultiply(&ssmap.mLightViewProj, &mLightView, &ssmap.mLightProj);
    
    V(m_pEffect->GetVariableByName("fLightZn")->AsScalar()->SetFloat(m_par.fLightZn));
	
    V(m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&ssmap.mLightViewProj));
    V(m_pEffect->GetVariableByName("mLightView")->AsMatrix()->SetMatrix((float *)&mLightView));
	V(m_pEffect->GetVariableByName("mLightProj")->AsMatrix()->SetMatrix((float *)&ssmap.mLightProj));

	//--------------------- for specular
	D3DXVECTOR3 vCameraInLight, vZero = D3DXVECTOR3(0, 0, 0);
	D3DXVec3TransformCoord(&vCameraInLight, &vZero, &mWorldViewInv);
	D3DXVec3TransformCoord(&vCameraInLight, &vCameraInLight, &mLightView);
	V(m_pEffect->GetVariableByName("VCameraInLight")->AsVector()->SetRawValue(&vCameraInLight, 0, sizeof(vCameraInLight)));
	//-------------------------------------------------------------------------------------------------------------------------

	//Originally these are set inside soft shadow map class, I moved them our for more neat design
    V(m_pEffect->GetVariableByName("TexHSM")->AsShaderResource()->SetResource(ssmap.m_pBigDepth2SRView));
    V(m_pEffect->GetVariableByName("TexDepthMap")->AsShaderResource()->SetResource(ssmap.m_pDepthSRView[0]));
    V(m_pEffect->GetVariableByName("TexPreviousResult")->AsShaderResource()->SetResource(m_pPreResult));
	
	D3DXMATRIX mClip2Tex;
    mClip2Tex = D3DXMATRIX( 0.5,    0, 0,   0,
						    0, -0.5, 0,   0,
							0,    0, 1,   0,
							0.5,  0.5, 0,   1 );
    D3DXMATRIX mLightViewProjClip2Tex, mLightProjClip2TexInv;
    D3DXMatrixMultiply(&mTmp, &ssmap.mLightProj, &mClip2Tex);
    D3DXMatrixInverse(&mLightProjClip2TexInv, NULL, &mTmp);
    V(m_pEffect->GetVariableByName("mLightProjClip2TexInv")->AsMatrix()->SetMatrix((float *)&mLightProjClip2TexInv));

	pDev10->IASetInputLayout(m_pMaxLayout);

    {
        unsigned iTmp = g_SampleUI.GetCheckBox(IDC_BTEXTURED)->GetChecked();
        V(m_pEffect->GetVariableByName("bTextured")->AsScalar()->SetRawValue(&iTmp, 0, sizeof(iTmp)));
        D3DXVECTOR4 vTmp = D3DXVECTOR4(1, 1, (float)iTmp, 1);
        V(m_pEffect->GetVariableByName("VLightFlux")->AsVector()->SetRawValue(&m_vec4LightColor, 0, sizeof(D3DXVECTOR4)));
    }

    V(m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&mWorldViewProj));

	float fTmp = (FLOAT)(g_fFilterSize*LIGHT_SCALE_FACTOR);
    V(m_pEffect->GetVariableByName("fFilterSize")->AsScalar()->SetFloat(fTmp));
    
	m_pEffect->GetVariableByName( "TexRadialArea" )->AsShaderResource()->SetResource(m_pAreaTextureRV);

	V(m_pEffect->GetVariableByName("TexPosInWorld")->AsShaderResource()->SetResource( m_pInputBuffer->m_pInputAttributes->m_pSRView0));
	V(m_pEffect->GetVariableByName("TexNormalInWorld")->AsShaderResource()->SetResource( m_pInputBuffer->m_pInputAttributes->m_pSRView1));
	V(m_pEffect->GetVariableByName("TexColor")->AsShaderResource()->SetResource( m_pInputBuffer->m_pInputAttributes->m_pSRView2));

	m_pHSMKernel->SetUseMyRT(true);
	m_pHSMKernel->OnD3D10FrameRender( m_pEffect,m_pEffect->GetTechniqueByName("RenderHSMKernel"),
   		                              pDev10,fTime,fElapsedTime,pUserContext);
	V(m_pEffect->GetVariableByName("TexHSMKernel")->AsShaderResource()->SetResource( m_pHSMKernel->m_pSRView ));

	const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc = DXUTGetDXGIBackBufferSurfaceDesc();
	V(m_pEffect->GetVariableByName("fScreenWidth")->AsScalar()->SetFloat(pBackBufferSurfaceDesc->Width));
	V(m_pEffect->GetVariableByName("fScreenHeight")->AsScalar()->SetFloat(pBackBufferSurfaceDesc->Height));


	pDev10->OMSetRenderTargets(1,&m_pRTV,NULL);
	float ClearColor[4] = { 1, 1, 1, 1 };
	pDev10->ClearRenderTargetView(m_pRTV, ClearColor);

	m_pShadowResult->SetUseMyRT(false);
	m_pShadowResult->OnD3D10FrameRender( m_pEffect,m_pEffect->GetTechniqueByName("SSMBackprojection"),
   										 pDev10,fTime,fElapsedTime,pUserContext);

}

void SilhouetteBPMSSMKernel::OnD3D10DestroyDevice()
{
	OnD3D10SwapChainReleasing(NULL);

    SAFE_RELEASE(m_pEffect);
    SAFE_RELEASE(m_pMaxLayout);
	SAFE_RELEASE(m_pAreaTextureRV);

	m_pHSMKernel->OnD3D10DestroyDevice();
	SAFE_DELETE(m_pHSMKernel);
	m_pShadowResult->OnD3D10DestroyDevice();
	SAFE_DELETE(m_pShadowResult);

}

