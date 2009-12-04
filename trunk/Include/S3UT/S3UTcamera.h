//----------------------------------------------------------------------------------
// File:   S3UTCamera.h
// Email:  sdkfeedback@S3Graphics.com
// 
// Copyright (c) 2007 S3Graphics Corporation. All rights reserved.
//
// TO  THE MAXIMUM  EXTENT PERMITTED  BY APPLICABLE  LAW, THIS SOFTWARE  IS PROVIDED
// *AS IS*  AND S3Graphics AND  ITS SUPPLIERS DISCLAIM  ALL WARRANTIES,  EITHER  EXPRESS
// OR IMPLIED, INCLUDING, BUT NOT LIMITED  TO, IMPLIED WARRANTIES OF MERCHANTABILITY
// AND FITNESS FOR A PARTICULAR PURPOSE.  IN NO EVENT SHALL  S3Graphics OR ITS SUPPLIERS
// BE  LIABLE  FOR  ANY  SPECIAL,  INCIDENTAL,  INDIRECT,  OR  CONSEQUENTIAL DAMAGES
// WHATSOEVER (INCLUDING, WITHOUT LIMITATION,  DAMAGES FOR LOSS OF BUSINESS PROFITS,
// BUSINESS INTERRUPTION, LOSS OF BUSINESS INFORMATION, OR ANY OTHER PECUNIARY LOSS)
// ARISING OUT OF THE  USE OF OR INABILITY  TO USE THIS SOFTWARE, EVEN IF S3Graphics HAS
// BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
//
//
//----------------------------------------------------------------------------------

#pragma once
#ifndef S3UTCAMERA_H
#define S3UTCAMERA_H

#include <dxutcamera.h>

class S3UTCamera : public CModelViewerCamera
{
public:
    // automatically set near and far planes according to object AABB
    // note that function uses view matrix passed from the outside, not the one
    // stored inside the camera
    virtual void SetProjParams(FLOAT fFOV, FLOAT fAspect, D3DXMATRIX mView, D3DXVECTOR3 vBBox[2]);
    void SetProjParams(D3DXMATRIX mView, D3DXVECTOR3 vBBox[2]);
	void SetProjParams(FLOAT fFOV, FLOAT fAspect, FLOAT fNear,	FLOAT fFar);
	void OnKeyboard(UINT nChar, bool bKeyDown, bool bAltDown, void* pUserContext);

    void SetModelRot(const D3DXMATRIX &m)
    { m_mModelRot = m; }
};

#endif // S3UTCAMERA_H
