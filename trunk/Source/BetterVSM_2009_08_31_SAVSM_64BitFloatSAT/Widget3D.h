//----------------------------------------------------------------------------------
// File:   Widget3D.h
// Author: Baoguang Yang
// 
// Copyright (c) 2009 _COMPANYNAME_ Corporation. All rights reserved.
// 
// Renders the light source, axis, view frustum and so on
// Self contained, independent of outside affections except those necessary parameters
//
//----------------------------------------------------------------------------------

#pragma once

#include <dxut.h>
#include <dxutgui.h>
#include <dxutsettingsdlg.h>
#include <sdkmisc.h>

class S3UTCamera;

struct SVertexTexcoords
{
    D3DXVECTOR3 Pos;
};

class Widget3D
{
public:
	Widget3D();
	HRESULT OnD3D10CreateDevice( ID3D10Device* pDev10, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
	HRESULT OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );
	void	OnD3D10SwapChainReleasing( void* pUserContext );
	void	OnD3D10DestroyDevice();
	void	OnD3D10FrameRender( ID3D10Device* pDev10,S3UTCamera &par_CameraRef,S3UTCamera &par_LCameraRef, float par_fFilterSize );
	~Widget3D(){};
private:
	void	DrawLightSource( ID3D10Device* pDev10,S3UTCamera &par_CameraRef,S3UTCamera &par_LCameraRef, float par_fFilterSize );
	ID3D10Effect				*m_pEffect;
	ID3D10RasterizerState		*m_pRenderState;


};
