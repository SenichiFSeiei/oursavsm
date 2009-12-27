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
public:
	S3UTCameraManager(){};
	~S3UTCameraManager();
	void ConfigCameras( char *fileName );
	void DumpCameraStatus( char *fileName ) const;
	S3UTCamera *Eye( int num );//start counting from 0

private:
	void Clear();
	vector<S3UTCamera *> m_aPtrCameras;
};
