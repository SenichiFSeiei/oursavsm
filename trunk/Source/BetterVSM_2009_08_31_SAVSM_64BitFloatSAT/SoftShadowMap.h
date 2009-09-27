//----------------------------------------------------------------------------------
// File:   S3UTMesh.h
// Author: Baoguang Yang
// 
// Copyright (c) 2009 S3Graphics Corporation. All rights reserved.
// 
// Contains code manipulating shadow map and 
// 1. HSM
// 2. MSSM
// 3. SAT
//
//----------------------------------------------------------------------------------

#ifndef SSMAP
#define SSMAP
#include <dxut.h>
#include <dxutgui.h>
#include <dxutsettingsdlg.h>

class S3UTMesh;
class S3UTCamera;

class SSMap
{
public:
    ID3D10Texture2D *m_pDepthTex[1], *m_pDepthMip2, *m_pBigDepth2; ///< textures for rendering
    ID3D10DepthStencilView *m_pDepthDSView[1]; ///< depth stencil view
    ID3D10RenderTargetView **m_pDepthMip2RTViews, *m_pBigDepth2RTView;
    ID3D10StateBlock *m_pOldRenderState; ///< we save rendering state here
    ID3D10RasterizerState *m_pRasterState; ///< render state we use to render shadow map
    ID3D10DepthStencilState *m_pDSState; ///< render state we use to render shadow map
    ID3D10ShaderResourceView *m_pDepthSRView[1], *m_pDepthMip2SRView, **m_pDepthMip2SRViews, *m_pBigDepth2SRView;
    int nMips; ///< number of depth mips (depends on the depth map resolution)

	//------ NBuffer ------------------------------------------------
	ID3D10Texture2D *m_pNBuffers;
	ID3D10ShaderResourceView *m_pNBufferSRView;
	ID3D10RenderTargetView **m_pNBufferRTViews;
	ID3D10ShaderResourceView **m_pNBufferSRViews;
	//---------------------------------------------------------------

	//------   VSM	 ------------------------------------------------
    ID3D10Texture2D *m_pVSMMip2;
	ID3D10RenderTargetView **m_pVSMMip2RTViews;
	ID3D10ShaderResourceView *m_pVSMMip2SRView, **m_pVSMMip2SRViews;
	//---------------------------------------------------------------

	//------   SAT VSM  ---------------------------------------------
	static const int NUM_SAT_TMP_TEX = 2;//with the scissor optimization, this number should always be 2
	ID3D10Texture2D *m_pSatTexes[NUM_SAT_TMP_TEX];
	ID3D10RenderTargetView *m_pSatRTViews[NUM_SAT_TMP_TEX];
	ID3D10ShaderResourceView *m_pSatSRViews[NUM_SAT_TMP_TEX];
	ID3D10ShaderResourceView *m_pSatSRView;
	static const int m_cSatRes = 1024;
	static const int m_cSampleBatch = 8;
	//---------------------------------------------------------------


	ID3D10Effect *m_pShadowMapEffect;

	int m_nDepthRes;
    ID3D10InputLayout *m_pDepthLayout; ///< layout with only POSITION semantic in it
    ID3D10EffectTechnique *m_pDRenderTechnique;
    SSMap();
    void OnDestroy();
    void OnWindowResize();

	void OnD3D10CreateDevice(ID3D10Device* pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void* pUserContext);

    //You can not remove this, this bool shows some magical affect to the entire code.
	//I'll find the root later. Too much unclear outer dependencies, oops!
    bool bAccurateShadow;
    D3DXMATRIX mLightViewProj, mLightProj;

   	void set_parameters( bool par_bBuildHSM, bool par_bBuildMSSM, bool par_bBuildSAT, bool par_bBuildVSM );
	void Render(ID3D10Device *a, S3UTMesh *b, S3UTCamera& d,float fTime, float fElapsedTime,bool dump_sm);
	bool m_bBuildHSM;
	bool m_bBuildMSSM;
	bool m_bBuildSAT;
	bool m_bBuildVSM;
	bool m_bShaderChanged;

	void PrepareBuildingHSM( ID3D10Device *par_pDev10 );
	void BuildHSM( ID3D10Device *par_pDev10 );
	void PrepareBuildingNBuffer( ID3D10Device *par_pDev10 );
	void BuildNBuffer( ID3D10Device *par_pDev10 );
	void PrepareBuildingVSM( ID3D10Device *par_pDev10 );
	void BuildVSM( ID3D10Device *par_pDev10 );
	void PrepareBuildingSAT( ID3D10Device *par_pDev10 );
	void BuildSAT( ID3D10Device *par_pDev10 );
	void CreateShader(ID3D10Device* pDev10);


};


#endif
