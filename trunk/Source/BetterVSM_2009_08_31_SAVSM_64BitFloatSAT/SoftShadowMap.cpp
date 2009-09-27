//#define DEBUG_SAT

#define _USE_MATH_DEFINES

#include <dxut.h>
#include <dxutgui.h>
#include <dxutsettingsdlg.h>
#include <sdkmisc.h>

#include "SoftShadowMap.h"
#include "CommonDef.h"
#include <S3UTmesh.h>
#include <S3UTcamera.h>

#ifdef  USE_INT_SAT
#ifdef DUAL_EVSM
#define SAT_FORMAT DXGI_FORMAT_R32G32B32A32_UINT
#else
#define SAT_FORMAT DXGI_FORMAT_R32G32_UINT
#endif
#else
#ifdef DISTRIBUTE_PRECISION
#define SAT_FORMAT DXGI_FORMAT_R32G32B32A32_FLOAT
#else
#define SAT_FORMAT DXGI_FORMAT_R32G32_FLOAT
#endif
#endif


SSMap::SSMap()
{
    ZeroMemory(this, sizeof(*this));
	m_nDepthRes = DEPTH_RES;
    nMips = (int)(log((double)m_nDepthRes) / M_LN2);
	m_pShadowMapEffect = NULL;
	m_bBuildHSM = false;
	m_bBuildMSSM = false;
	m_bBuildSAT = true;
	m_bBuildVSM = false;
	m_pDRenderTechnique = NULL;
	m_bShaderChanged = false;
}

void SSMap::set_parameters( bool par_bBuildHSM, bool par_bBuildMSSM, bool par_bBuildSAT, bool par_bBuildVSM )
{
	m_bBuildHSM = par_bBuildHSM;
	m_bBuildMSSM = par_bBuildMSSM;
	m_bBuildSAT = par_bBuildSAT;
	m_bBuildVSM = par_bBuildVSM;
}

void SSMap::CreateShader(ID3D10Device* pDev10)
{
	HRESULT hr;
    WCHAR str[MAX_PATH];
    ID3D10Blob *pErrors;
	SAFE_RELEASE( m_pShadowMapEffect );

	V(DXUTFindDXSDKMediaFileCch(str, MAX_PATH, L"softshadowmap.fx"));
    if (D3DX10CreateEffectFromFile(str, NULL, NULL, "fx_4_0", D3D10_SHADER_DEBUG|D3D10_SHADER_SKIP_OPTIMIZATION, 0, pDev10, NULL, NULL, &m_pShadowMapEffect, &pErrors, &hr) != S_OK)
    {
        MessageBoxA(NULL, (char *)pErrors->GetBufferPointer(), "Compilation error", MB_OK);
        exit(0);
    }

}


void SSMap::OnD3D10CreateDevice(ID3D10Device* pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void* pUserContext)
{
	CreateShader( pDev10 );

}

void SSMap::OnWindowResize()
{
    SAFE_RELEASE(m_pOldRenderState);
}

void SSMap::PrepareBuildingNBuffer( ID3D10Device *par_pDev10 )
{
    HRESULT hr;
    m_pNBufferRTViews = new ID3D10RenderTargetView *[nMips];
	m_pNBufferSRViews = new ID3D10ShaderResourceView *[nMips];
	D3D10_TEXTURE2D_DESC NBDesc =
    {
		m_nDepthRes, //UINT Width;
        m_nDepthRes, //UINT Height;
        1,//UINT MipLevels;
        nMips,//UINT ArraySize;
        DXGI_FORMAT_R32G32_FLOAT,//DXGI_FORMAT Format;
        {1, 0}, //DXGI_SAMPLE_DESC SampleDesc;
        D3D10_USAGE_DEFAULT, //D3D10_USAGE Usage;
        D3D10_BIND_SHADER_RESOURCE | D3D10_BIND_RENDER_TARGET,//UINT BindFlags;
        0,//UINT CPUAccessFlags;
        0,//UINT MiscFlags;
    };
	V(par_pDev10->CreateTexture2D(&NBDesc, NULL, &m_pNBuffers));

	D3D10_SHADER_RESOURCE_VIEW_DESC NBsrViewDesc;
	NBsrViewDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
	NBsrViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2DARRAY;
	NBsrViewDesc.Texture2DArray.ArraySize = nMips;
	NBsrViewDesc.Texture2DArray.MostDetailedMip = 0;
	NBsrViewDesc.Texture2DArray.MipLevels = 1;
	NBsrViewDesc.Texture2DArray.FirstArraySlice = 0;
	V(par_pDev10->CreateShaderResourceView(m_pNBuffers, &NBsrViewDesc, &m_pNBufferSRView));

	D3D10_RENDER_TARGET_VIEW_DESC NBrtViewDesc;
    NBrtViewDesc.ViewDimension = D3D10_RTV_DIMENSION_TEXTURE2DARRAY;
	NBrtViewDesc.Texture2DArray.MipSlice = 0;
	NBrtViewDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
	NBrtViewDesc.Texture2DArray.ArraySize = 1;
	NBsrViewDesc.Texture2DArray.ArraySize = 1;
    for (int im = 0; im < nMips; ++im)
    {
		NBrtViewDesc.Texture2DArray.FirstArraySlice = im;
		V(par_pDev10->CreateRenderTargetView(m_pNBuffers, &NBrtViewDesc, &m_pNBufferRTViews[im]));
		NBsrViewDesc.Texture2DArray.FirstArraySlice = im;
		V(par_pDev10->CreateShaderResourceView(m_pNBuffers, &NBsrViewDesc, &m_pNBufferSRViews[im]));
    }
}
void SSMap::PrepareBuildingHSM( ID3D10Device *par_pDev10 )
{
    HRESULT hr;

	m_pDepthMip2SRViews = new ID3D10ShaderResourceView *[nMips];
    m_pDepthMip2RTViews = new ID3D10RenderTargetView *[nMips];
	// create render targets
    D3D10_TEXTURE2D_DESC rtDesc =
    {
        m_nDepthRes, //UINT Width;
        m_nDepthRes, //UINT Height;
        nMips,//UINT MipLevels;
        1,//UINT ArraySize;
        DXGI_FORMAT_R32G32_FLOAT,//DXGI_FORMAT Format;
        {1, 0}, //DXGI_SAMPLE_DESC SampleDesc;
        D3D10_USAGE_DEFAULT, //D3D10_USAGE Usage;
        D3D10_BIND_SHADER_RESOURCE | D3D10_BIND_RENDER_TARGET,//UINT BindFlags;
        0,//UINT CPUAccessFlags;
        0,//UINT MiscFlags;
    };
    V(par_pDev10->CreateTexture2D(&rtDesc, NULL, &m_pDepthMip2));
    rtDesc.Width = (rtDesc.Width * 3) / 2;
    rtDesc.MipLevels = 1;
    V(par_pDev10->CreateTexture2D(&rtDesc, NULL, &m_pBigDepth2));

    D3D10_SHADER_RESOURCE_VIEW_DESC srViewDesc;
    srViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
    srViewDesc.Texture2D.MostDetailedMip = 0;
    srViewDesc.Texture2D.MipLevels = nMips;
    srViewDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
    V(par_pDev10->CreateShaderResourceView(m_pDepthMip2, &srViewDesc, &m_pDepthMip2SRView));

    srViewDesc.Texture2D.MipLevels = 1;
    D3D10_RENDER_TARGET_VIEW_DESC rtViewDesc;
    rtViewDesc.ViewDimension = D3D10_RTV_DIMENSION_TEXTURE2D;
    for (int im = 0; im < nMips; ++im)
    {
        srViewDesc.Texture2D.MostDetailedMip = im;
        srViewDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
        V(par_pDev10->CreateShaderResourceView(m_pDepthMip2, &srViewDesc, &m_pDepthMip2SRViews[im]));
        rtViewDesc.Texture2D.MipSlice = im;
        rtViewDesc.Format = DXGI_FORMAT_R32G32_FLOAT;
        V(par_pDev10->CreateRenderTargetView(m_pDepthMip2, &rtViewDesc, &m_pDepthMip2RTViews[im]));
    }
    rtViewDesc.Texture2D.MipSlice = 0;
    V(par_pDev10->CreateRenderTargetView(m_pBigDepth2, &rtViewDesc, &m_pBigDepth2RTView));
    srViewDesc.Texture2D.MostDetailedMip = 0;
    V(par_pDev10->CreateShaderResourceView(m_pBigDepth2, &srViewDesc, &m_pBigDepth2SRView));

}

void SSMap::PrepareBuildingSAT( ID3D10Device *par_pDev10 )
{
    HRESULT hr;
	D3D10_TEXTURE2D_DESC SATDesc =
    {
		m_cSatRes, //UINT Width;
        m_cSatRes, //UINT Height;
        1,//UINT MipLevels;
        1,//UINT ArraySize;
        SAT_FORMAT,//DXGI_FORMAT Format;
        {1, 0}, //DXGI_SAMPLE_DESC SampleDesc;
        D3D10_USAGE_DEFAULT, //D3D10_USAGE Usage;
        D3D10_BIND_SHADER_RESOURCE | D3D10_BIND_RENDER_TARGET,//UINT BindFlags;
        0,//UINT CPUAccessFlags;
        0,//UINT MiscFlags;
    };

	for( int i = 0; i < NUM_SAT_TMP_TEX; ++i )
	{
		V(par_pDev10->CreateTexture2D(&SATDesc, NULL, &m_pSatTexes[i]));
	}

	D3D10_SHADER_RESOURCE_VIEW_DESC SATsrViewDesc;
	SATsrViewDesc.Format = SAT_FORMAT;
	SATsrViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
	SATsrViewDesc.Texture2D.MostDetailedMip = 0;
	SATsrViewDesc.Texture2D.MipLevels = 1;
	for( int i = 0; i < NUM_SAT_TMP_TEX; ++i )
	{
		V(par_pDev10->CreateShaderResourceView(m_pSatTexes[i], &SATsrViewDesc, &m_pSatSRViews[i]));
	}

	D3D10_RENDER_TARGET_VIEW_DESC SATrtViewDesc;
    SATrtViewDesc.ViewDimension = D3D10_RTV_DIMENSION_TEXTURE2D;
	SATrtViewDesc.Texture2D.MipSlice = 0;
	SATrtViewDesc.Format = SAT_FORMAT;
	for( int  i = 0; i < NUM_SAT_TMP_TEX; ++i )
	{
		V(par_pDev10->CreateRenderTargetView(m_pSatTexes[i], &SATrtViewDesc, &m_pSatRTViews[i]));
	}
}

void SSMap::PrepareBuildingVSM( ID3D10Device *par_pDev10 )
{
    HRESULT hr;

	m_pVSMMip2SRViews = new ID3D10ShaderResourceView *[nMips];
    m_pVSMMip2RTViews = new ID3D10RenderTargetView *[nMips];
	// create render targets
    D3D10_TEXTURE2D_DESC rtDesc =
    {
        m_nDepthRes, //UINT Width;
        m_nDepthRes, //UINT Height;
        nMips,//UINT MipLevels;
        1,//UINT ArraySize;
        DXGI_FORMAT_R32G32B32A32_FLOAT,//DXGI_FORMAT Format;
        {1, 0}, //DXGI_SAMPLE_DESC SampleDesc;
        D3D10_USAGE_DEFAULT, //D3D10_USAGE Usage;
        D3D10_BIND_SHADER_RESOURCE | D3D10_BIND_RENDER_TARGET,//UINT BindFlags;
        0,//UINT CPUAccessFlags;
        0,//UINT MiscFlags;
    };
    V(par_pDev10->CreateTexture2D(&rtDesc, NULL, &m_pVSMMip2));
    D3D10_SHADER_RESOURCE_VIEW_DESC srViewDesc;
    srViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
    srViewDesc.Texture2D.MostDetailedMip = 0;
    srViewDesc.Texture2D.MipLevels = nMips;
    srViewDesc.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
    V(par_pDev10->CreateShaderResourceView(m_pVSMMip2, &srViewDesc, &m_pVSMMip2SRView));

    srViewDesc.Texture2D.MipLevels = 1;
    D3D10_RENDER_TARGET_VIEW_DESC rtViewDesc;
    rtViewDesc.ViewDimension = D3D10_RTV_DIMENSION_TEXTURE2D;
    for (int im = 0; im < nMips; ++im)
    {
        srViewDesc.Texture2D.MostDetailedMip = im;
        srViewDesc.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
        V(par_pDev10->CreateShaderResourceView(m_pVSMMip2, &srViewDesc, &m_pVSMMip2SRViews[im]));
        rtViewDesc.Texture2D.MipSlice = im;
        rtViewDesc.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
        V(par_pDev10->CreateRenderTargetView(m_pVSMMip2, &rtViewDesc, &m_pVSMMip2RTViews[im]));
    }
}


void SSMap::BuildNBuffer( ID3D10Device *par_pDev10 )
{
	HRESULT hr;
	ID3D10EffectTechnique *pDReworkTechnique2 = m_pShadowMapEffect->GetTechniqueByName("ReworkDepth2");

	D3D10_VIEWPORT vp;
    vp.Height = m_nDepthRes;
    vp.Width = m_nDepthRes;
    vp.MinDepth = 0;
    vp.MaxDepth = 1;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;

    V(m_pShadowMapEffect->GetVariableByName("DepthTex0")->AsShaderResource()->SetResource(m_pDepthSRView[0]));

	par_pDev10->RSSetViewports(1, &vp);
	par_pDev10->OMSetRenderTargets(1, &m_pNBufferRTViews[0], NULL);
	V(pDReworkTechnique2->GetPassByName("ConvertDepthWithAdj")->Apply(0));
	for (int im = 0; ; )
    {
        par_pDev10->Draw(3, 0);
        if (++im == nMips)
        { break; }      
		V(m_pShadowMapEffect->GetVariableByName("nBufferLevel")->AsScalar()->SetInt(im-1)) ;
        V(m_pShadowMapEffect->GetVariableByName("DepthNBuffer")->AsShaderResource()->SetResource(m_pNBufferSRViews[im - 1]));
        par_pDev10->OMSetRenderTargets(1, &m_pNBufferRTViews[im], NULL);
        V(pDReworkTechnique2->GetPassByName("CreateNBuffer")->Apply(0));
    }
}
void SSMap::BuildSAT( ID3D10Device *par_pDev10 )
{
	HRESULT hr;

	D3D10_VIEWPORT vp;
    vp.Height = m_cSatRes;
    vp.Width = m_cSatRes;
    vp.MinDepth = 0;
    vp.MaxDepth = 1;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;
	par_pDev10->RSSetViewports(1, &vp);

	ID3D10EffectTechnique *pSATTechnique2 = m_pShadowMapEffect->GetTechniqueByName("RenderSAT");

    int src_tex_idx = 0;
	int dst_tex_idx = 1;

	V(m_pShadowMapEffect->GetVariableByName("DepthTex0")->AsShaderResource()->SetResource(m_pDepthSRView[0]));
	par_pDev10->OMSetRenderTargets(1, &m_pSatRTViews[src_tex_idx], NULL);
	float ClearColor[4] = { 1, 1, 0, 0 };
#ifndef DEBUG_SAT
	V(pSATTechnique2->GetPassByName("ConvertDepth")->Apply(0));
	par_pDev10->Draw(3, 0);
#endif

	//first src is not SatSRViews, but the original depth map
	V(m_pShadowMapEffect->GetVariableByName("nSampleNum")->AsScalar()->SetInt(m_cSampleBatch));
	int log2_sample_batch = static_cast<int>(log(static_cast<double>(m_cSampleBatch))/log(static_cast<double>(2)));
	int num_passes = 0; 
	unsigned int current_res = m_cSatRes;
	while( current_res > 0 )
	{
		++num_passes;
		current_res >>= log2_sample_batch;
	}

	int sample_interval = 1;
	int left_bound = 0;
	for (int pass_idx = 0; pass_idx < num_passes; ++pass_idx)//not iterating passes in a single technique, but those passes doing recursively double
	{
		V(m_pShadowMapEffect->GetVariableByName("SatSrcTex")->AsShaderResource()->SetResource(m_pSatSRViews[src_tex_idx]));
		par_pDev10->OMSetRenderTargets(1, &m_pSatRTViews[dst_tex_idx], NULL);
		V(m_pShadowMapEffect->GetVariableByName("nSatSampleInterval")->AsScalar()->SetFloat( sample_interval )) ;
		V(pSATTechnique2->GetPassByName("HorizontalPass")->Apply(0));
		D3D10_RECT Region = {left_bound, 0, m_cSatRes, m_cSatRes};
		par_pDev10->RSSetScissorRects(1, &Region);
        par_pDev10->Draw(3, 0);
		++src_tex_idx;
		++dst_tex_idx;
		src_tex_idx %= NUM_SAT_TMP_TEX;
		dst_tex_idx %= NUM_SAT_TMP_TEX;
		sample_interval *= m_cSampleBatch;
		left_bound = sample_interval / m_cSampleBatch;
	}
	sample_interval = 1;
	int bottom_bound = 0;
	for (int pass_idx = 0; pass_idx < num_passes; ++pass_idx)//not iterating passes in a single technique, but those passes doing recursively double
	{
		V(m_pShadowMapEffect->GetVariableByName("SatSrcTex")->AsShaderResource()->SetResource(m_pSatSRViews[src_tex_idx]));
		par_pDev10->OMSetRenderTargets(1, &m_pSatRTViews[dst_tex_idx], NULL);
		V(m_pShadowMapEffect->GetVariableByName("nSatSampleInterval")->AsScalar()->SetFloat( sample_interval )) ;
		V(pSATTechnique2->GetPassByName("VerticalPass")->Apply(0));
		D3D10_RECT Region = {0, bottom_bound, m_cSatRes, m_cSatRes};
		par_pDev10->RSSetScissorRects(1, &Region);
        par_pDev10->Draw(3, 0);
		++src_tex_idx;
		++dst_tex_idx;
		src_tex_idx %= NUM_SAT_TMP_TEX;
		dst_tex_idx %= NUM_SAT_TMP_TEX;
		sample_interval *= m_cSampleBatch;
		bottom_bound = sample_interval / m_cSampleBatch;
	}

}
void SSMap::BuildHSM( ID3D10Device *par_pDev10 )
{
	HRESULT hr;
	ID3D10EffectTechnique *pDReworkTechnique2 = m_pShadowMapEffect->GetTechniqueByName("ReworkDepth2");

	D3D10_VIEWPORT vp;
    vp.Height = m_nDepthRes;
    vp.Width = m_nDepthRes;
    vp.MinDepth = 0;
    vp.MaxDepth = 1;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;

	// create mipmap pyramid
    V(m_pShadowMapEffect->GetVariableByName("DepthTex0")->AsShaderResource()->SetResource(m_pDepthSRView[0]));
    par_pDev10->OMSetRenderTargets(1, &m_pDepthMip2RTViews[0], NULL);
    ID3D10Buffer *pNullVBuf[] = { NULL };
    unsigned pStrides[] = { 0 };
    unsigned pOffsets[] = { 0 };
    par_pDev10->IASetVertexBuffers(0, 1, pNullVBuf, pStrides, pOffsets);
    par_pDev10->IASetInputLayout(NULL);
    V(pDReworkTechnique2->GetPassByName("ConvertDepth")->Apply(0));
    for (int im = 0; ; )
    {
        par_pDev10->Draw(3, 0);
        if (++im == nMips)
        { break; }
        vp.Width = (vp.Height /= 2);
        par_pDev10->RSSetViewports(1, &vp);
        V(m_pShadowMapEffect->GetVariableByName("DepthMip2")->AsShaderResource()->SetResource(m_pDepthMip2SRViews[im - 1]));
        par_pDev10->OMSetRenderTargets(1, &m_pDepthMip2RTViews[im], NULL);
        V(pDReworkTechnique2->GetPassByName("CreateMip")->Apply(0));
    }

	//Not sure if this will affect codes below
	//Magic, without this, shadow map could not be drawn correctly
	ID3D10RenderTargetView *pNullRTView = NULL;
    par_pDev10->OMSetRenderTargets(1, &pNullRTView, NULL);

    V(m_pShadowMapEffect->GetVariableByName("DepthMip2")->AsShaderResource()->SetResource(m_pDepthMip2SRView));
    V(pDReworkTechnique2->GetPassByName("ConvertToBig")->Apply(0));
    vp.Height = m_nDepthRes;
    vp.Width = (m_nDepthRes * 3) / 2;
    vp.MinDepth = 0;
    vp.MaxDepth = 1;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;
    par_pDev10->RSSetViewports(1, &vp);
    par_pDev10->OMSetRenderTargets(1, &m_pBigDepth2RTView, NULL);
    
	float ClearColor[4] = { 1, 1, 1, 1 };
	par_pDev10->ClearRenderTargetView(m_pBigDepth2RTView,ClearColor);
    par_pDev10->Draw(3, 0);

}

void SSMap::BuildVSM( ID3D10Device *par_pDev10 )
{
	HRESULT hr;
	ID3D10EffectTechnique *pDReworkTechnique2 = m_pShadowMapEffect->GetTechniqueByName("ReworkVSM2");

	D3D10_VIEWPORT vp;
    vp.Height = m_nDepthRes;
    vp.Width = m_nDepthRes;
    vp.MinDepth = 0;
    vp.MaxDepth = 1;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;

	// create mipmap pyramid
    V(m_pShadowMapEffect->GetVariableByName("DepthTex0")->AsShaderResource()->SetResource(m_pDepthSRView[0]));
    par_pDev10->OMSetRenderTargets(1, &m_pVSMMip2RTViews[0], NULL);
    ID3D10Buffer *pNullVBuf[] = { NULL };
    unsigned pStrides[] = { 0 };
    unsigned pOffsets[] = { 0 };
    par_pDev10->IASetVertexBuffers(0, 1, pNullVBuf, pStrides, pOffsets);
    par_pDev10->IASetInputLayout(NULL);
    V(pDReworkTechnique2->GetPassByName("ConvertDepth")->Apply(0));
    for (int im = 0; ; )
    {
        par_pDev10->Draw(3, 0);
        if (++im == nMips)
        { break; }
        vp.Width = (vp.Height /= 2);
        par_pDev10->RSSetViewports(1, &vp);
        V(m_pShadowMapEffect->GetVariableByName("VSMMip2")->AsShaderResource()->SetResource(m_pVSMMip2SRViews[im - 1]));
        par_pDev10->OMSetRenderTargets(1, &m_pVSMMip2RTViews[im], NULL);
        V(pDReworkTechnique2->GetPassByName("CreateMip")->Apply(0));
    }

	//Not sure if this will affect codes below
	//Magic, without this, shadow map could not be drawn correctly
	ID3D10RenderTargetView *pNullRTView = NULL;
    par_pDev10->OMSetRenderTargets(1, &pNullRTView, NULL);
}

void SSMap::Render(ID3D10Device *pDev10, S3UTMesh *pMesh, S3UTCamera &g_LCameraRef,float fTime,float fElapsedTime,bool dump_sm)
{
	if( m_bShaderChanged )
	{
		CreateShader(pDev10);
		m_bShaderChanged = false;
	}

	HRESULT hr;
	mLightProj = *g_LCameraRef.GetProjMatrix();

    D3DXMATRIX mTranslate,mLightView;

	D3DXMatrixInverse(&mTranslate, NULL, g_LCameraRef.GetWorldMatrix());
	D3DXMatrixMultiply(&mLightView, &mTranslate, g_LCameraRef.GetViewMatrix());

	D3DXMatrixMultiply(&mLightViewProj, &mLightView, &mLightProj);


    V(m_pShadowMapEffect->GetVariableByName("mViewProj")->AsMatrix()->SetMatrix((float *)&mLightViewProj));
    V(m_pShadowMapEffect->GetVariableByName("mLightView")->AsMatrix()->SetMatrix((float *)&mLightView));
#ifdef USE_LINEAR_Z
	D3DXMATRIX mClip2Tex, mTmp;
    mClip2Tex = D3DXMATRIX( 0.5,    0, 0,   0,
						    0, -0.5, 0,   0,
							0,    0, 1,   0,
							0.5,  0.5, 0,   1 );
    D3DXMATRIX mLightViewProjClip2Tex, mLightProjClip2TexInv;
    D3DXMatrixMultiply(&mTmp, &mLightProj, &mClip2Tex);
    D3DXMatrixInverse(&mLightProjClip2TexInv, NULL, &mTmp);
    V(m_pShadowMapEffect->GetVariableByName("mLightProjClip2TexInv")->AsMatrix()->SetMatrix((float *)&mLightProjClip2TexInv));
	V(m_pShadowMapEffect->GetVariableByName("Zf")->AsScalar()->SetFloat(g_LCameraRef.GetFarClip()));
	V(m_pShadowMapEffect->GetVariableByName("Zn")->AsScalar()->SetFloat(g_LCameraRef.GetNearClip()));
#endif

    m_pDRenderTechnique = m_pShadowMapEffect->GetTechniqueByName("RenderDepth");
    if (m_pDepthTex[0] == NULL)
    {
        // create render targets
        D3D10_TEXTURE2D_DESC rtDesc =
        {
            m_nDepthRes, //UINT Width;
            m_nDepthRes, //UINT Height;
            1,//UINT MipLevels;
            1,//UINT ArraySize;
            DXGI_FORMAT_R32_TYPELESS,//DXGI_FORMAT Format;
            {1, 0}, //DXGI_SAMPLE_DESC SampleDesc;
            D3D10_USAGE_DEFAULT, //D3D10_USAGE Usage;
            D3D10_BIND_SHADER_RESOURCE | D3D10_BIND_DEPTH_STENCIL,//UINT BindFlags;
            0,//UINT CPUAccessFlags;
            0,//UINT MiscFlags;
        };
        V(pDev10->CreateTexture2D(&rtDesc, NULL, &m_pDepthTex[0]));

        D3D10_DEPTH_STENCIL_VIEW_DESC dsViewDesc;
        D3D10_SHADER_RESOURCE_VIEW_DESC srViewDesc;
        dsViewDesc.Format = DXGI_FORMAT_D32_FLOAT;
        srViewDesc.Format = DXGI_FORMAT_R32_FLOAT;
        dsViewDesc.ViewDimension = D3D10_DSV_DIMENSION_TEXTURE2D;
        srViewDesc.ViewDimension = D3D10_SRV_DIMENSION_TEXTURE2D;
        dsViewDesc.Texture2D.MipSlice = 0;
        srViewDesc.Texture2D.MostDetailedMip = 0;
        srViewDesc.Texture2D.MipLevels = 1;
        V(pDev10->CreateDepthStencilView(m_pDepthTex[0], &dsViewDesc, &m_pDepthDSView[0]));
        V(pDev10->CreateShaderResourceView(m_pDepthTex[0], &srViewDesc, &m_pDepthSRView[0]));

        static const D3D10_INPUT_ELEMENT_DESC depth_layout[] =
        {
            { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0, D3D10_INPUT_PER_VERTEX_DATA, 0 },
        };
        D3D10_PASS_DESC PassDesc;
        V(m_pDRenderTechnique->GetPassByIndex(0)->GetDesc(&PassDesc));
        V(pDev10->CreateInputLayout(depth_layout, 1, PassDesc.pIAInputSignature, PassDesc.IAInputSignatureSize, &m_pDepthLayout));

        SAFE_RELEASE(m_pRasterState);
        D3D10_RASTERIZER_DESC RasterState;
        RasterState.FillMode = D3D10_FILL_SOLID;
        RasterState.CullMode = SHADOWMAP_CULL;
        RasterState.FrontCounterClockwise = true;
        RasterState.DepthBias = false;
        RasterState.DepthBiasClamp = 0;
        RasterState.SlopeScaledDepthBias = 0;
        RasterState.DepthClipEnable = true;
        RasterState.ScissorEnable = true;
        RasterState.MultisampleEnable = false;
        RasterState.AntialiasedLineEnable = false;
        V(pDev10->CreateRasterizerState(&RasterState, &m_pRasterState));

        SAFE_RELEASE(m_pDSState);
        D3D10_DEPTH_STENCIL_DESC DSState;
        ZeroMemory(&DSState, sizeof(DSState));
        DSState.DepthEnable = true;
        DSState.DepthWriteMask = D3D10_DEPTH_WRITE_MASK_ALL;
        DSState.DepthFunc = D3D10_COMPARISON_LESS_EQUAL;
        V(pDev10->CreateDepthStencilState(&DSState, &m_pDSState));

		if( m_bBuildHSM )
		{
			PrepareBuildingHSM( pDev10 );
		}
		if( m_bBuildVSM )
		{
			PrepareBuildingVSM( pDev10 );
		}
		if( m_bBuildSAT )
		{
			PrepareBuildingSAT( pDev10 );
		}
		if( m_bBuildMSSM )
		{
			PrepareBuildingNBuffer( pDev10 );
		}

    }
    if (m_pOldRenderState == NULL)
    {
        D3D10_STATE_BLOCK_MASK SBMask;
        ZeroMemory(&SBMask, sizeof(SBMask));
        SBMask.RSViewports = true;
        SBMask.OMRenderTargets = true;
        SBMask.RSRasterizerState = true;
        V(D3D10CreateStateBlock(pDev10, &SBMask, &m_pOldRenderState));
    }
    V(m_pOldRenderState->Capture());

    D3D10_VIEWPORT vp;
    vp.Height = m_nDepthRes;
    vp.Width = m_nDepthRes;
    vp.MinDepth = 0;
    vp.MaxDepth = 1;
    vp.TopLeftX = 0;
    vp.TopLeftY = 0;
    pDev10->RSSetViewports(1, &vp);

    // render depth
    pDev10->RSSetState(m_pRasterState);
    pDev10->OMSetDepthStencilState(m_pDSState, 0);
    ID3D10RenderTargetView *pNullRTView = NULL;
    pDev10->OMSetRenderTargets(1, &pNullRTView, m_pDepthDSView[0]);
    pDev10->IASetInputLayout(m_pDepthLayout);
    pDev10->ClearDepthStencilView(m_pDepthDSView[0], D3D10_CLEAR_DEPTH, 1.0, 0);
	pMesh->Render( MAX_BONE_MATRICES,
					(FLOAT)SCALE,
					m_pShadowMapEffect,
					m_pShadowMapEffect->GetTechniqueByName(SUIT_TECH_NAME),
					m_pShadowMapEffect->GetTechniqueByName(BODY_TECH_NAME),
					m_pDRenderTechnique,
					m_pDRenderTechnique,
					&mLightViewProj,
					pDev10,
					fTime,fElapsedTime,NULL,false );

	if( m_bBuildHSM )
	{
		BuildHSM( pDev10 );
	}
	if( m_bBuildVSM )
	{
		BuildVSM( pDev10 );
	}
	if( m_bBuildMSSM )
	{
		BuildNBuffer( pDev10 );
	}
	if( m_bBuildSAT )
	{
		BuildSAT( pDev10 );
	}
    pDev10->OMSetRenderTargets(1, &pNullRTView, NULL);

    static bool bSaved = true;
	static int iidx = 0;
    if (0)
    {
        bSaved = true;
        ID3D10Texture2D *pTexture = NULL;
        D3D10_TEXTURE2D_DESC textureDesc;
        m_pSatTexes[0]->GetDesc(&textureDesc);
        textureDesc.Format = DXGI_FORMAT_R32_FLOAT;
        textureDesc.CPUAccessFlags = D3D10_CPU_ACCESS_READ;
        textureDesc.Usage = D3D10_USAGE_STAGING;
        textureDesc.BindFlags = 0;
        V(pDev10->CreateTexture2D(&textureDesc, NULL, &pTexture));
        pDev10->CopyResource(pTexture, m_pSatTexes[0]);
		//if( 0 == iidx )
			D3DX10SaveTextureToFile(pTexture, D3DX10_IFF_DDS, L"e:\\firstsm.dds");
		/*else if( 1 == iidx )
			D3DX10SaveTextureToFile(pTexture, D3DX10_IFF_DDS, L"c:\\fff1.dds");
		else if( 2 == iidx )
			D3DX10SaveTextureToFile(pTexture, D3DX10_IFF_DDS, L"c:\\fff2.dds");
		else if( 3 == iidx )
			D3DX10SaveTextureToFile(pTexture, D3DX10_IFF_DDS, L"c:\\fff3.dds");
		iidx ++;
		iidx = iidx%NUM_LIGHT;*/

    }

    V(m_pOldRenderState->Apply());
}
void SSMap::OnDestroy()
{
    SAFE_RELEASE(m_pDepthTex[0]);
    SAFE_RELEASE(m_pDepthSRView[0]);
    SAFE_RELEASE(m_pDepthDSView[0]);
    
	for( int i = 0; i < NUM_SAT_TMP_TEX; ++i )
	{
		SAFE_RELEASE(m_pSatTexes[i]);
		SAFE_RELEASE(m_pSatSRViews[i]);
		SAFE_RELEASE(m_pSatRTViews[i]);
	}

    SAFE_RELEASE(m_pDepthMip2);
    SAFE_RELEASE(m_pDepthMip2SRView);

	SAFE_RELEASE(m_pVSMMip2);
    SAFE_RELEASE(m_pVSMMip2SRView);

    SAFE_RELEASE(m_pNBuffers);
    SAFE_RELEASE(m_pNBufferSRView);

    if (m_pDepthMip2RTViews)
    {
        for (int im = 0; im < nMips; ++im)
        {
            SAFE_RELEASE(m_pDepthMip2RTViews[im]);
            SAFE_RELEASE(m_pDepthMip2SRViews[im]);
        }
    }
    if (m_pVSMMip2RTViews)
    {
        for (int im = 0; im < nMips; ++im)
        {
            SAFE_RELEASE(m_pVSMMip2RTViews[im]);
            SAFE_RELEASE(m_pVSMMip2SRViews[im]);
        }
    }
	if (m_pNBufferRTViews)
	{
		for (int im = 0; im < nMips; ++im)
		{
            SAFE_RELEASE(m_pNBufferRTViews[im]);
            SAFE_RELEASE(m_pNBufferSRViews[im]);
		}
	}

    SAFE_DELETE_ARRAY(m_pDepthMip2RTViews);
    SAFE_DELETE_ARRAY(m_pDepthMip2SRViews);
    
	SAFE_DELETE_ARRAY(m_pVSMMip2RTViews);
    SAFE_DELETE_ARRAY(m_pVSMMip2SRViews);
    
	SAFE_DELETE_ARRAY(m_pNBufferRTViews);
    SAFE_DELETE_ARRAY(m_pNBufferSRViews);

    SAFE_RELEASE(m_pOldRenderState); ///< we save rendering state here
    SAFE_RELEASE(m_pDepthLayout); ///< layout with only POSITION semantic in it
    SAFE_RELEASE(m_pRasterState); ///< render state we use to render shadow map
    SAFE_RELEASE(m_pDSState); ///< render state we use to render shadow map

    SAFE_RELEASE(m_pBigDepth2);
    SAFE_RELEASE(m_pBigDepth2SRView);
    SAFE_RELEASE(m_pBigDepth2RTView);
	SAFE_RELEASE(m_pShadowMapEffect);

    ZeroMemory(this, sizeof(*this));
}
