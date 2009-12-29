//----------------------------------------------------------------------------------
// File:   S3UTCameraManager.h
// Author: Baoguang Yang
// 
// Copyright (c) 2009 _COMPANYNAME_ Corporation. All rights reserved.
// 
// Manages all the cameras
//
//----------------------------------------------------------------------------------

#pragma once
#include <vector>
#include <dxut.h>
#include <dxutgui.h>
#include <dxutsettingsdlg.h>
#include <sdkmisc.h>

using namespace std;

class S3UTCamera;

class S3UTCameraManager
{
	static const int HANDLE_BASE = 10000;
public:
	S3UTCameraManager(){};
	~S3UTCameraManager();
	
	void ConfigCameras( char *fileName );
	void DumpCameraStatus( char *fileName ) const;
	void SetupCameraUI( CDXUTDialog &camUI ) const;
	void SyncToCameraUI(CDXUTDialog &camUI);
	
	S3UTCamera *Camera( int num );
	S3UTCamera *Eye( int num );//start counting from 0
	S3UTCamera *ActiveEye();//the 1st active eye camera.
	int CameraCount() const { return static_cast<int>(m_aPtrCameras.size()); };

	void OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext );


private:
	void Clear();
	vector<S3UTCamera *> m_aPtrCameras;
};
