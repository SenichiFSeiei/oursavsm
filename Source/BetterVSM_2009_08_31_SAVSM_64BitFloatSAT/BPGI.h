#pragma once

#include "CommonDef.h"
#include "SoftShadowMap.h"
#include "BasicSSMAlgorithm.h"
#include "RenderObject.h"
#include "DepthObject.h"
#include "OGRE_LAYOUT.h"


class BPGlobalIllumination:public BasicSSMAlgorithm
{
public:
	ID3D10Effect *m_pEffect;
	ID3D10InputLayout *m_pMaxLayout;
	ID3D10ShaderResourceView*           m_pAreaTextureRV;
	RenderObject	*m_pScreenPixelPos;
	RenderObject	*m_pHSMKernel;
	
	RenderObject	*m_pScreenPixelPosHalf;
	RenderObject	*m_pHSMKernelHalf;
	
	RenderObject	*m_pScreenPixelPosQuarter;
	RenderObject	*m_pHSMKernelQuarter;

	RenderObject	*m_pFloorVBufferOrigin;
	RenderObject	*m_pFloorVBufferHalf;
	RenderObject	*m_pFloorVBufferQuarter;

	DepthObject		*m_pDepthBuffer;


	BPGlobalIllumination();
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
	void OnD3D10DestroyDevice( void* pUserContext );
	HRESULT OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );



};

BPGlobalIllumination::BPGlobalIllumination()
{
	m_pEffect = NULL;
	m_pMaxLayout = NULL;
	m_pAreaTextureRV = NULL;
	m_pScreenPixelPos = NULL;
	m_pDepthBuffer = NULL;
	m_pHSMKernel = NULL;

	m_pFloorVBufferOrigin	=	NULL;
	m_pFloorVBufferHalf		=	NULL;
	m_pFloorVBufferQuarter	=	NULL;

	m_pScreenPixelPosHalf	=	NULL;
	m_pHSMKernelHalf		=	NULL;

	m_pScreenPixelPosQuarter	=	NULL;
	m_pHSMKernelQuarter			=	NULL;

}

HRESULT BPGlobalIllumination::OnD3D10CreateDevice(ID3D10Device *pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void *pUserContext)
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
    V_RETURN(DXUTFindDXSDKMediaFileCch(str, MAX_PATH, (BPGI_EFFECT_FILE_NAME) ));
    ID3D10Blob *pErrors;
    if (D3DX10CreateEffectFromFile(str, NULL, NULL, "fx_4_0", D3D10_SHADER_DEBUG|D3D10_SHADER_SKIP_OPTIMIZATION, 0, pDev10, NULL, NULL, &m_pEffect, &pErrors, &hr) != S_OK)
    {
        MessageBoxA(NULL, (char *)pErrors->GetBufferPointer(), "Compilation error", MB_OK);
        exit(0);
    }
    D3D10_PASS_DESC PassDesc;
    V_RETURN(m_pEffect->GetTechniqueByName(SILHOUETTE_BP_SCENE_TECH)->GetPassByIndex(0)->GetDesc(&PassDesc));
    V_RETURN(pDev10->CreateInputLayout(scenemeshlayout, 3, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &m_pMaxLayout));

    //load texture for occluded area computation
	hr = D3DX10CreateShaderResourceViewFromFile( pDev10, L"areaT.dds", NULL, NULL, &m_pAreaTextureRV, NULL );
    if( FAILED(hr) )
        return hr;
	
	m_pScreenPixelPos = new RenderObject( "RenderScreenPixelPos" );
	m_pScreenPixelPos ->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);

	m_pScreenPixelPosHalf = new RenderObject( "RenderScreenPixelPos" );
	m_pScreenPixelPosHalf ->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);

	m_pScreenPixelPosQuarter = new RenderObject( "RenderScreenPixelPos" );
	m_pScreenPixelPosQuarter ->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);
	
	m_pHSMKernel = new RenderObject( "RenderHSMKernel" );
	m_pHSMKernel ->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);
	
	m_pHSMKernelHalf = new RenderObject( "RenderHSMKernel" );
	m_pHSMKernelHalf ->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);
	
	m_pHSMKernelQuarter = new RenderObject( "RenderHSMKernel" );
	m_pHSMKernelQuarter ->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);

	m_pDepthBuffer = new DepthObject( "RenderDepth" );
	m_pDepthBuffer->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);
	
	//select a render object to render downscaled shadow buffer for the floor
	m_pFloorVBufferOrigin = new RenderObject( "RenderFloor" );
	m_pFloorVBufferOrigin->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);

	m_pFloorVBufferHalf = new RenderObject( "RenderFloor" );
	m_pFloorVBufferHalf->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);

	m_pFloorVBufferQuarter = new RenderObject( "RenderFloor" );
	m_pFloorVBufferQuarter->OnD3D10CreateDevice( m_pEffect,pDev10, pBackBufferSurfaceDesc, pUserContext);

	return S_OK;

}

HRESULT BPGlobalIllumination::OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
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

	m_pScreenPixelPos->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	//only position need 32 bit floating point, 16bit is enouth for others. save memory/traffic.
	rtDesc_scrpos.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;
	m_pHSMKernel->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	m_pFloorVBufferOrigin->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);

	//create surfaces for HALF sized buffers
	rtDesc_scrpos.Width = pBackBufferSurfaceDesc->Width/2;
	rtDesc_scrpos.Height = pBackBufferSurfaceDesc->Height/2;
	rtDesc_scrpos.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
	m_pScreenPixelPosHalf->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	//only position need 32 bit floating point, 16bit is enouth for others. save memory/traffic.
	rtDesc_scrpos.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;
	m_pHSMKernelHalf->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	m_pFloorVBufferHalf->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);

	//create surfaces for HALF sized buffers
	rtDesc_scrpos.Width = pBackBufferSurfaceDesc->Width/4;
	rtDesc_scrpos.Height = pBackBufferSurfaceDesc->Height/4;
	rtDesc_scrpos.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
	m_pScreenPixelPosQuarter->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	//only position need 32 bit floating point, 16bit is enouth for others. save memory/traffic.
	rtDesc_scrpos.Format = DXGI_FORMAT_R16G16B16A16_FLOAT;
	m_pHSMKernelQuarter->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	m_pFloorVBufferQuarter->OnD3D10SwapChainResized( rtDesc_scrpos, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);

	D3D10_TEXTURE2D_DESC rtDesc_DepthBuffer =
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

	m_pDepthBuffer->OnD3D10SwapChainResized( rtDesc_DepthBuffer, pDev10, pSwapChain, pBackBufferSurfaceDesc, pUserContext);
	return S_OK;
}

void BPGlobalIllumination::OnD3D10FrameRender(bool render_ogre, 
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
    
    V(m_pEffect->GetVariableByName("g_fLightZn")->AsScalar()->SetFloat(m_par.fLightZn));
	
    V(m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&ssmap.mLightViewProj));
    V(m_pEffect->GetVariableByName("mLightView")->AsMatrix()->SetMatrix((float *)&mLightView));
	V(m_pEffect->GetVariableByName("mLightProj")->AsMatrix()->SetMatrix((float *)&ssmap.mLightProj));

	//--------------------- for specular
	D3DXVECTOR3 vCameraInLight, vZero = D3DXVECTOR3(0, 0, 0);
	D3DXVec3TransformCoord(&vCameraInLight, &vZero, &mWorldViewInv);
	D3DXVec3TransformCoord(&vCameraInLight, &vCameraInLight, &mLightView);
	V(m_pEffect->GetVariableByName("g_vCameraInLight")->AsVector()->SetRawValue(&vCameraInLight, 0, sizeof(vCameraInLight)));
	//-------------------------------------------------------------------------------------------------------------------------


	//Originally these are set inside soft shadow map class, I moved them our for more neat design
    V(m_pEffect->GetVariableByName("DepthMip2")->AsShaderResource()->SetResource(ssmap.m_pBigDepth2SRView));
    V(m_pEffect->GetVariableByName("DepthTex0")->AsShaderResource()->SetResource(ssmap.m_pDepthSRView[0]));
    V(m_pEffect->GetVariableByName("g_txPreviousResult")->AsShaderResource()->SetResource(m_pPreResult));
	
	D3DXMATRIX mClip2Tex;
    mClip2Tex = D3DXMATRIX( 0.5,    0, 0,   0,
						    0, -0.5, 0,   0,
							0,    0, 1,   0,
							0.5,  0.5, 0,   1 );
    D3DXMATRIX mLightViewProjClip2Tex, mLightProjClip2TexInv;
    D3DXMatrixMultiply(&mLightViewProjClip2Tex, &ssmap.mLightViewProj, &mClip2Tex);
    V(m_pEffect->GetVariableByName("mLightViewProjClip2Tex")->AsMatrix()->SetMatrix((float *)&mLightViewProjClip2Tex));
    D3DXMatrixMultiply(&mTmp, &ssmap.mLightProj, &mClip2Tex);
    D3DXMatrixInverse(&mLightProjClip2TexInv, NULL, &mTmp);
    V(m_pEffect->GetVariableByName("mLightProjClip2TexInv")->AsMatrix()->SetMatrix((float *)&mLightProjClip2TexInv));

	pDev10->IASetInputLayout(m_pMaxLayout);

    {
        unsigned iTmp = g_SampleUI.GetCheckBox(IDC_BTEXTURED)->GetChecked();
        V(m_pEffect->GetVariableByName("bTextured")->AsScalar()->SetRawValue(&iTmp, 0, sizeof(iTmp)));
        D3DXVECTOR4 vTmp = D3DXVECTOR4(1, 1, (float)iTmp, 1);
        V(m_pEffect->GetVariableByName("g_vLightFlux")->AsVector()->SetRawValue(&m_vec4LightColor, 0, sizeof(D3DXVECTOR4)));
        V(m_pEffect->GetVariableByName("g_vMaterialKd")->AsVector()->SetRawValue(&vTmp, 0, sizeof(D3DXVECTOR4)));
    }

    V(m_pEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&mWorldViewProj));
    {
        D3DXVECTOR3 vLgtPos, vZero = D3DXVECTOR3(0, 0, 0);
        D3DXMATRIX mLightViewInv;
        D3DXMatrixInverse(&mLightViewInv, NULL, &mLightView);
        D3DXVec3TransformCoord(&vLgtPos, &vZero, &mLightViewInv);
        V(m_pEffect->GetVariableByName("g_vLightPos")->AsVector()->SetRawValue(&vLgtPos, 0, sizeof(vLgtPos)));
    }

	float fTmp = (FLOAT)(g_fFilterSize*LIGHT_SCALE_FACTOR);
    V(m_pEffect->GetVariableByName("g_fFilterSize")->AsScalar()->SetFloat(fTmp));
    V(m_pEffect->GetVariableByName("g_fDoubleFilterSizeRev")->AsScalar()->SetFloat((FLOAT)(1.0 / (2 * fTmp))));
    
	ID3D10EffectShaderResourceVariable *pTexture = m_pEffect->GetVariableByName("DiffuseTex")->AsShaderResource();
	m_pEffect->GetVariableByName( "g_txArea" )->AsShaderResource()->SetResource(m_pAreaTextureRV);

	m_pDepthBuffer->Clear(pDev10);
	m_pScreenPixelPos->OnD3D10FrameRender(	m_pEffect,
									m_pEffect->GetTechniqueByName(	SUIT_POS_TECH_NAME ),
									m_pEffect->GetTechniqueByName(	BODY_POS_TECH_NAME ),
									m_pEffect->GetTechniqueByName(	SCENE_POS_TECH_NAME ),
									&mWorldViewProj,
									&g_MeshScene,m_pDepthBuffer->m_pDSView,pDev10, fTime, fElapsedTime, pUserContext);
	V(m_pEffect->GetVariableByName("ShadowMapPos")->AsShaderResource()->SetResource( m_pScreenPixelPos->m_pSRView ));

	m_pDepthBuffer->Clear(pDev10);	
	m_pHSMKernel->OnD3D10FrameRender(	m_pEffect,
										m_pEffect->GetTechniqueByName(	SUIT_KERNEL_TECH_NAME ),
										m_pEffect->GetTechniqueByName(	BODY_KERNEL_TECH_NAME ),
										m_pEffect->GetTechniqueByName(	SCENE_KERNEL_TECH_NAME ),
										&mWorldViewProj,
										&g_MeshScene,/*m_pDepthBuffer->m_pDSView*/DXUTGetD3D10DepthStencilView(),pDev10, fTime, fElapsedTime, pUserContext);
	
	const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc = DXUTGetDXGIBackBufferSurfaceDesc();
	V(m_pEffect->GetVariableByName("g_fScreenWidth")->AsScalar()->SetFloat(pBackBufferSurfaceDesc->Width));
	V(m_pEffect->GetVariableByName("g_fScreenHeight")->AsScalar()->SetFloat(pBackBufferSurfaceDesc->Height));


	if( g_fFilterSize < 0.5 )
	{
		V(m_pEffect->GetVariableByName("g_txHSMKernel")->AsShaderResource()->SetResource( m_pHSMKernel->m_pSRView ));
		pDev10->OMSetRenderTargets(1,&m_pRTV,DXUTGetD3D10DepthStencilView());
		float ClearColor[4] = { 1, 1, 1, 1 };
		pDev10->ClearRenderTargetView(m_pRTV, ClearColor);
		pDev10->ClearDepthStencilView(DXUTGetD3D10DepthStencilView(), D3D10_CLEAR_DEPTH, 1.0, 0);

		g_MeshScene.Render( MAX_BONE_MATRICES,
							(FLOAT)SCALE,
							m_pEffect,
							m_pEffect->GetTechniqueByName(SUIT_TECH_NAME),
							m_pEffect->GetTechniqueByName(BODY_TECH_NAME),
							m_pEffect->GetTechniqueByName(SILHOUETTE_BP_SCENE_TECH),
							m_pEffect->GetTechniqueByName(SILHOUETTE_BP_SCENE_OBJECT_TECH),
							&mWorldViewProj,
							pDev10,
							fTime,fElapsedTime,pUserContext, true);

	}
	else 
	{
		if( g_fFilterSize < 1.0 )
		{
			m_pDepthBuffer->Clear(pDev10);
			g_MeshScene.set_parameters(false,false,false);
			m_pScreenPixelPosHalf->OnD3D10FrameRender(	m_pEffect,
											m_pEffect->GetTechniqueByName(	SUIT_POS_TECH_NAME ),
											m_pEffect->GetTechniqueByName(	BODY_POS_TECH_NAME ),
											m_pEffect->GetTechniqueByName(	SCENE_POS_TECH_NAME ),
											&mWorldViewProj,
											&g_MeshScene,m_pDepthBuffer->m_pDSView,pDev10, fTime, fElapsedTime, pUserContext);
			V(m_pEffect->GetVariableByName("ShadowMapPos")->AsShaderResource()->SetResource( m_pScreenPixelPosHalf->m_pSRView ));

			m_pDepthBuffer->Clear(pDev10);	
			m_pHSMKernelHalf->OnD3D10FrameRender(	m_pEffect,
												m_pEffect->GetTechniqueByName(	SUIT_KERNEL_TECH_NAME ),
												m_pEffect->GetTechniqueByName(	BODY_KERNEL_TECH_NAME ),
												m_pEffect->GetTechniqueByName(	SCENE_KERNEL_TECH_NAME ),
												&mWorldViewProj,
												&g_MeshScene,m_pDepthBuffer->m_pDSView,pDev10, fTime, fElapsedTime, pUserContext);
			V(m_pEffect->GetVariableByName("g_txHSMKernel")->AsShaderResource()->SetResource( m_pHSMKernelHalf->m_pSRView ));
			
			pDev10->OMSetRenderTargets(1,&m_pFloorVBufferHalf->m_pRTView,m_pDepthBuffer->m_pDSView);
			float ClearColor[4] = { 1, 1, 1, 1 };
			pDev10->ClearRenderTargetView(m_pFloorVBufferHalf->m_pRTView, ClearColor);
			pDev10->ClearDepthStencilView(m_pDepthBuffer->m_pDSView, D3D10_CLEAR_DEPTH, 1.0, 0);
			g_MeshScene.Render( MAX_BONE_MATRICES,
								(FLOAT)SCALE,
								m_pEffect,
								m_pEffect->GetTechniqueByName(SUIT_TECH_NAME),
								m_pEffect->GetTechniqueByName(BODY_TECH_NAME),
								m_pEffect->GetTechniqueByName(SILHOUETTE_BP_SCENE_VF_TECH),
								m_pEffect->GetTechniqueByName(SILHOUETTE_BP_SCENE_OBJECT_TECH),
								&mWorldViewProj,
								pDev10,
								fTime,fElapsedTime,pUserContext, true);
			V(m_pEffect->GetVariableByName("g_txFloorShadowBuffer")->AsShaderResource()->SetResource( m_pFloorVBufferHalf->m_pSRView ));
		}
		else
		{
			m_pDepthBuffer->Clear(pDev10);
			g_MeshScene.set_parameters(false,false,false);
			m_pScreenPixelPosQuarter->OnD3D10FrameRender(	m_pEffect,
											m_pEffect->GetTechniqueByName(	SUIT_POS_TECH_NAME ),
											m_pEffect->GetTechniqueByName(	BODY_POS_TECH_NAME ),
											m_pEffect->GetTechniqueByName(	SCENE_POS_TECH_NAME ),
											&mWorldViewProj,
											&g_MeshScene,m_pDepthBuffer->m_pDSView,pDev10, fTime, fElapsedTime, pUserContext);
			V(m_pEffect->GetVariableByName("ShadowMapPos")->AsShaderResource()->SetResource( m_pScreenPixelPosQuarter->m_pSRView ));

			m_pDepthBuffer->Clear(pDev10);	
			m_pHSMKernelQuarter->OnD3D10FrameRender(	m_pEffect,
												m_pEffect->GetTechniqueByName(	SUIT_KERNEL_TECH_NAME ),
												m_pEffect->GetTechniqueByName(	BODY_KERNEL_TECH_NAME ),
												m_pEffect->GetTechniqueByName(	SCENE_KERNEL_TECH_NAME ),
												&mWorldViewProj,
												&g_MeshScene,m_pDepthBuffer->m_pDSView,pDev10, fTime, fElapsedTime, pUserContext);
			V(m_pEffect->GetVariableByName("g_txHSMKernel")->AsShaderResource()->SetResource( m_pHSMKernelQuarter->m_pSRView ));
			
			pDev10->OMSetRenderTargets(1,&m_pFloorVBufferQuarter->m_pRTView,m_pDepthBuffer->m_pDSView);
			float ClearColor[4] = { 1, 1, 1, 1 };
			pDev10->ClearRenderTargetView(m_pFloorVBufferQuarter->m_pRTView, ClearColor);
			pDev10->ClearDepthStencilView(m_pDepthBuffer->m_pDSView, D3D10_CLEAR_DEPTH, 1.0, 0);
			g_MeshScene.Render( MAX_BONE_MATRICES,
								(FLOAT)SCALE,
								m_pEffect,
								m_pEffect->GetTechniqueByName(SUIT_TECH_NAME),
								m_pEffect->GetTechniqueByName(BODY_TECH_NAME),
								m_pEffect->GetTechniqueByName(SILHOUETTE_BP_SCENE_VF_TECH),
								m_pEffect->GetTechniqueByName(SILHOUETTE_BP_SCENE_OBJECT_TECH),
								&mWorldViewProj,
								pDev10,
								fTime,fElapsedTime,pUserContext, true);

			V(m_pEffect->GetVariableByName("g_txFloorShadowBuffer")->AsShaderResource()->SetResource( m_pFloorVBufferQuarter->m_pSRView ));
		}

		
		pDev10->OMSetRenderTargets(1,&m_pRTV,DXUTGetD3D10DepthStencilView());

		D3D10_VIEWPORT vp;
		vp.Height = pBackBufferSurfaceDesc->Height;
		vp.Width = pBackBufferSurfaceDesc->Width;
		vp.MinDepth = 0;
		vp.MaxDepth = 1;
		vp.TopLeftX = 0;
		vp.TopLeftY = 0;
		pDev10->RSSetViewports(1, &vp);

		V(m_pEffect->GetVariableByName("ShadowMapPos")->AsShaderResource()->SetResource( m_pScreenPixelPos->m_pSRView ));
		V(m_pEffect->GetVariableByName("g_txHSMKernel")->AsShaderResource()->SetResource( m_pHSMKernel->m_pSRView ));

		g_MeshScene.Render( MAX_BONE_MATRICES,
							(FLOAT)SCALE,
							m_pEffect,
							m_pEffect->GetTechniqueByName(SUIT_TECH_NAME),
							m_pEffect->GetTechniqueByName(BODY_TECH_NAME),
							m_pEffect->GetTechniqueByName(UPSAMPLE_TECH),
							m_pEffect->GetTechniqueByName(UPSAMPLE_TECH),
							&mWorldViewProj,
							pDev10,
							fTime,fElapsedTime,pUserContext, true);

		g_MeshScene.set_parameters(render_ogre,render_scene, false);
		g_MeshScene.Render( MAX_BONE_MATRICES,
							(FLOAT)SCALE,
							m_pEffect,
							m_pEffect->GetTechniqueByName(SUIT_TECH_NAME),
							m_pEffect->GetTechniqueByName(BODY_TECH_NAME),
							m_pEffect->GetTechniqueByName(SILHOUETTE_BP_SCENE_TECH),
							m_pEffect->GetTechniqueByName(SILHOUETTE_BP_SCENE_OBJECT_TECH),
							&mWorldViewProj,
							pDev10,
							fTime,fElapsedTime,pUserContext, true);

	}

}

void BPGlobalIllumination::OnD3D10DestroyDevice( void* pUserContext )
{
    SAFE_RELEASE(m_pEffect);
    SAFE_RELEASE(m_pMaxLayout);
	SAFE_RELEASE(m_pAreaTextureRV);
	m_pScreenPixelPos->OnD3D10DestroyDevice(pUserContext);
	SAFE_DELETE(m_pScreenPixelPos);
	m_pScreenPixelPosHalf->OnD3D10DestroyDevice(pUserContext);
	SAFE_DELETE(m_pScreenPixelPosHalf);
	m_pScreenPixelPosQuarter->OnD3D10DestroyDevice(pUserContext);
	SAFE_DELETE(m_pScreenPixelPosQuarter);

	m_pHSMKernel->OnD3D10DestroyDevice(pUserContext);
	SAFE_DELETE(m_pHSMKernel);
	m_pHSMKernelHalf->OnD3D10DestroyDevice(pUserContext);
	SAFE_DELETE(m_pHSMKernelHalf);
	m_pHSMKernelQuarter->OnD3D10DestroyDevice(pUserContext);
	SAFE_DELETE(m_pHSMKernelQuarter);

	m_pFloorVBufferOrigin->OnD3D10DestroyDevice(pUserContext);
	m_pFloorVBufferHalf->OnD3D10DestroyDevice(pUserContext);
	m_pFloorVBufferQuarter->OnD3D10DestroyDevice(pUserContext);
	SAFE_DELETE(m_pFloorVBufferOrigin);
	SAFE_DELETE(m_pFloorVBufferHalf);
	SAFE_DELETE(m_pFloorVBufferQuarter);

	m_pDepthBuffer->OnD3D10DestroyDevice(pUserContext);
	SAFE_DELETE(m_pDepthBuffer);

}

