//----------------------------------------------------------------------------------
// File:   S3UTcamera.h
// Author: Baoguang Yang
// 
// Copyright (c) 2009 _COMPANYNAME_ Corporation. All rights reserved.
//
// Cameras are also considered as lights, so they have light properties
// like m_bCastShadow, m_fLightSize
//
//----------------------------------------------------------------------------------

#pragma once
#ifndef S3UTCAMERA_H
#define S3UTCAMERA_H

#include <string>
#include <dxutcamera.h>

using namespace std;

class S3UTCamera : public CModelViewerCamera
{
public:
	enum CameraType
	{
		eLight,
		eEye,
		eUnknown
	};

    virtual void SetProjParams(FLOAT fFOV, FLOAT fAspect, D3DXMATRIX mView, D3DXVECTOR3 vBBox[2]);
    void SetProjParams(D3DXMATRIX mView, D3DXVECTOR3 vBBox[2]);
	void SetProjParams(FLOAT fFOV, FLOAT fAspect, FLOAT fNear,	FLOAT fFar);
	void OnKeyboard(UINT nChar, bool bKeyDown, bool bAltDown, void* pUserContext);
    void SetModelRot(const D3DXMATRIX &m) { m_mModelRot = m; }

	CameraType GetCamType()	const { return m_eCamType; };
	void SetCamType( CameraType camType ) { m_eCamType = camType; };

	string GetCamName() const { return m_sName; };
	void SetCamName( const string& camName ) { m_sName = camName; };
	void SetCamName( const char *camName ) { m_sName = string( camName ); };

	bool IsCastShadow() const { return m_bCastShadow; };
	void SetCastShadow( bool bCastShadow ) { m_bCastShadow = bCastShadow; };

	float GetLightSize() const { return m_fLightSize; };
	void  SetLightSize( float lightSize ) { m_fLightSize = lightSize; };


private:
	CameraType	m_eCamType;
	string		m_sName;
	bool		m_bCastShadow;
	float		m_fLightSize;
};

#endif // S3UTCAMERA_H
