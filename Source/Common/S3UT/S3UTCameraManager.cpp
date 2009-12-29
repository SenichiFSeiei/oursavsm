//----------------------------------------------------------------------------------
// File:   S3UTCameraManager.cpp
// Author: Baoguang Yang
// 
// Copyright (c) 2009 _COMPANYNAME_ Corporation. All rights reserved.
//
//----------------------------------------------------------------------------------
#include <Winnls.h>

#include <DXUT.h>
#include "S3UTcamera.h"
#include "S3UTCameraManager.h"
#include <algorithm>
#include <assert.h>

void S3UTCameraManager::ConfigCameras( char *fileName )
{
	char sCameraName[100];
	char sCameraType[100];
	memset( sCameraName, 0, sizeof(sCameraName) );
	memset( sCameraType, 0, sizeof(sCameraType) );
	FILE *fp = fopen(fileName,"r");
	if( !fp )
		printf("Fail to open %s and cameras could not be initialized, please double check if it exists.", fileName);
	while( fscanf( fp, "%s %s", sCameraName, sCameraType ) > 0 )
	{
		char sPropertyName[100];
		S3UTCamera *pCamera = new S3UTCamera();

		if( strcmp( sCameraType, "light" ) == 0 )
			pCamera->SetCamType( S3UTCamera::eLight );
		else if( strcmp( sCameraType, "eye" ) == 0 )
			pCamera->SetCamType( S3UTCamera::eEye );
		else
			pCamera->SetCamType( S3UTCamera::eUnknown );

		pCamera->SetCamName( sCameraName );

		int nCastShadow = 0;
		assert(fscanf(fp,"%s %d", sPropertyName, &nCastShadow));
		pCamera->SetCastShadow( nCastShadow == 1?true:false );

		D3DXVECTOR3 vPosition;
		D3DXVECTOR3 vLookAt;
		assert(fscanf(fp,"%s %f %f %f", sPropertyName, &vPosition.x, &vPosition.y, &vPosition.z));
		assert(fscanf(fp,"%s %f %f %f", sPropertyName, &vLookAt.x, &vLookAt.y, &vLookAt.z));
		pCamera->SetViewParams(&vPosition, &vLookAt);

		float lightSize = 0;
		assert(fscanf(fp,"%s %f", sPropertyName, &lightSize));
		pCamera->SetLightSize(lightSize);

		float zNear = 0;
		assert(fscanf(fp,"%s %f", sPropertyName, &zNear));
		float zFar = 0;
		assert(fscanf(fp,"%s %f", sPropertyName, &zFar));
		float fieldOfView = 0;
		assert(fscanf(fp,"%s %f", sPropertyName, &fieldOfView));
		float aspectRatio = 0;
		assert(fscanf(fp,"%s %f", sPropertyName, &aspectRatio));
		pCamera->SetProjParams(fieldOfView, aspectRatio, zNear, zFar);

		m_aPtrCameras.push_back(pCamera);

	}
	fclose(fp);
}

class DumpSingleCameraStatus
{
public:
	DumpSingleCameraStatus( FILE *fp ) : m_pFile( fp ) {};
	void operator() ( S3UTCamera *pCamera ) const
	{
		assert(fprintf(m_pFile,"%s\t",pCamera->GetCamName().c_str()));

		if( pCamera->GetCamType() == S3UTCamera::eLight )
			assert(fprintf(m_pFile,"light\n"));
		else if( pCamera->GetCamType() == S3UTCamera::eEye )
			assert(fprintf(m_pFile,"eye\n"));
		else
			assert(fprintf(m_pFile,"unknown\n"));
		
		assert(fprintf(m_pFile,"CastShadow\t%d\n",pCamera->IsCastShadow()?1:0));

		D3DXVECTOR3 vPosition = *pCamera->GetEyePt();
		assert(fprintf(m_pFile,"Position\t%f %f %f\n",vPosition.x,vPosition.y,vPosition.z));
		D3DXVECTOR3 vLookAt = *pCamera->GetLookAtPt();
		assert(fprintf(m_pFile,"AtPosition\t%f %f %f\n",vLookAt.x,vLookAt.y,vLookAt.z));

		float lightSize = pCamera->GetLightSize();
		assert(fprintf(m_pFile,"Size\t%f\n",lightSize));
		float zNear = pCamera->GetNearClip();
		assert(fprintf(m_pFile,"ZNear\t%f\n",zNear));
		float zFar = pCamera->GetFarClip();
		assert(fprintf(m_pFile,"ZFar\t%f\n",zFar));
		float fieldOfView = pCamera->GetFOV();
		assert(fprintf(m_pFile,"FieldOfView\t%f\n",fieldOfView));
		float aspectRatio = pCamera->GetAspectRatio();
		assert(fprintf(m_pFile,"AspectRatio\t%f\n\n",aspectRatio));
	}
private:
	FILE *m_pFile;

};
void S3UTCameraManager::DumpCameraStatus( char *fileName ) const
{
	char sCameraName[100];
	char sCameraType[100];
	memset( sCameraName, 0, sizeof(sCameraName) );
	memset( sCameraType, 0, sizeof(sCameraType) );
	FILE *fp = fopen(fileName,"w");
	if( !fp )
		printf("Fail to open %s and camera status could not be dumped, please double check if it exists.", fileName);
	
	vector<S3UTCamera *>::const_iterator iter_begin = m_aPtrCameras.begin(), iter_end = m_aPtrCameras.end();
	for_each(iter_begin,iter_end,DumpSingleCameraStatus(fp));
	fclose(fp);
}

void S3UTCameraManager::Clear()
{
	vector<S3UTCamera *>::const_iterator iter = m_aPtrCameras.begin(), iter_end = m_aPtrCameras.end();
	for(;iter!=iter_end;++iter)
	{
		if( *iter )
			delete (*iter);
	}
}

S3UTCameraManager::~S3UTCameraManager()
{
	Clear();
}

S3UTCamera* S3UTCameraManager::Eye( int num )
{
	vector<S3UTCamera *>::const_iterator iter = m_aPtrCameras.begin(), iter_end = m_aPtrCameras.end();
	int lightIdx = -1;
	for(;iter!=iter_end;++iter)
	{
		if( (*iter)->GetCamType() == S3UTCamera::eEye )
		{
			++lightIdx;
			if( num == lightIdx )
			{
				printf("Find the %d eye!\n", num);
				return (*iter);
			}
		}
	}
	printf("Does not find the required eye, there are only %d eye(s) available, please double check the data file!\n", lightIdx+1);
	return NULL;
}

class IsACameraOf
{
public:
	IsACameraOf( S3UTCamera::CameraType camType ):m_tCamType(camType){};
	bool operator() ( S3UTCamera *pCam ) const
	{
		return pCam->GetCamType() == m_tCamType;
	}
private:
	S3UTCamera::CameraType m_tCamType;
};

class IsAnActiveCameraOf
{
public:
	IsAnActiveCameraOf( S3UTCamera::CameraType camType ):m_tCamType(camType){};
	bool operator() ( S3UTCamera *pCam ) const
	{
		IsACameraOf isSuchCam( m_tCamType );
		return isSuchCam( pCam )&&pCam->IsActive();
	}
private:
	S3UTCamera::CameraType m_tCamType;
};

S3UTCamera *S3UTCameraManager::ActiveEye()//the 1st active eye camera.
{
	vector<S3UTCamera *>::iterator iter = find_if( m_aPtrCameras.begin(),m_aPtrCameras.end(),IsAnActiveCameraOf(S3UTCamera::eEye));
	if( iter == m_aPtrCameras.end() )
		iter = find_if( m_aPtrCameras.begin(),m_aPtrCameras.end(),IsACameraOf(S3UTCamera::eEye));
	return (*iter);
}

void S3UTCameraManager::OnD3D10SwapChainResized( ID3D10Device* pDev10, IDXGISwapChain *pSwapChain, const DXGI_SURFACE_DESC* pBackBufferSurfaceDesc, void* pUserContext )
{
	vector<S3UTCamera *>::const_iterator iter = m_aPtrCameras.begin(), iter_end = m_aPtrCameras.end();
	for(;iter!=iter_end;++iter)
	{
		//this is not absolutely right. since, lights should have there own width and height,
		//but it's OK, SetWindow only affects the mouse interaction with UI
		( *iter )->	SetWindow(pBackBufferSurfaceDesc->Width, pBackBufferSurfaceDesc->Height);
			
	}
}

S3UTCamera *S3UTCameraManager::Camera( int num )
{
	if( num<0 || num>CameraCount() )
	{
		printf( "Invalid camera index, should be from 0 to %d.\n",CameraCount() );
		return 0;
	}
	return m_aPtrCameras[num];
}

void S3UTCameraManager::SetupCameraUI( CDXUTDialog &camUI ) const
{	
	int charWidth = 5;
	int textHeight = 22;
	int colSpace = 10;
	D3DXCOLOR fontColor( 0.3f, 0.7f, 0.1f, 1.0f );

	camUI.AddStatic(8, L"Light UI", 0, 0, 200, 22);
	camUI.GetControl(8)->SetTextColor( fontColor );

	int camIdx = 0;
	vector<S3UTCamera *>::const_iterator iter = m_aPtrCameras.begin(), iter_end = m_aPtrCameras.end();
	for(;iter!=iter_end;++iter)
	{
		int textCursorX = 0;
		int len = strlen((*iter)->GetCamName().c_str()) + 1;
		int nwLen = MultiByteToWideChar(CP_ACP,0,(*iter)->GetCamName().c_str(),len,NULL,0);   
		TCHAR   lpszCamName[256];   
		MultiByteToWideChar(CP_ACP,0,(*iter)->GetCamName().c_str(),len,lpszCamName,nwLen);   

		camUI.AddStatic( HANDLE_BASE+camIdx, lpszCamName, textCursorX*charWidth, (camIdx+1)*textHeight, 200, 22 );
		camUI.GetControl(HANDLE_BASE+camIdx)->SetTextColor( fontColor );

		textCursorX += colSpace;

		if( (*iter)->GetCamType() == S3UTCamera::eEye )
			camUI.AddStatic( HANDLE_BASE+camIdx, L"Eye", textCursorX*charWidth, (camIdx+1)*textHeight, 200, 22 );
		else if( (*iter)->GetCamType() == S3UTCamera::eLight )
			camUI.AddStatic( HANDLE_BASE+camIdx, L"Light", textCursorX*charWidth, (camIdx+1)*textHeight, 200, 22 );
		camUI.GetControl(HANDLE_BASE+camIdx)->SetTextColor( fontColor );

		textCursorX += 3*colSpace;
		camUI.AddCheckBox( HANDLE_BASE+CameraCount()+camIdx, L"Active", textCursorX*charWidth, (camIdx+1)*textHeight, 100, 22, (*iter)->IsActive());
		
		textCursorX += 2*colSpace;
		camUI.AddCheckBox( HANDLE_BASE+2*CameraCount()+camIdx, L"Controllable", textCursorX*charWidth, (camIdx+1)*textHeight, 100, 22, (*iter)->IsControllable());

		++camIdx;
	}

}

void S3UTCameraManager::SyncToCameraUI(CDXUTDialog &camUI)
{
	int camIdx = 0;
	vector<S3UTCamera *>::iterator iter = m_aPtrCameras.begin(), iter_end = m_aPtrCameras.end();
	for(;iter!=iter_end;++iter)
	{
		bool isActive = camUI.GetCheckBox( HANDLE_BASE+CameraCount()+camIdx )->GetChecked();
		bool isControllable = camUI.GetCheckBox( HANDLE_BASE+2*CameraCount()+camIdx )->GetChecked();
		(*iter)->SetActive( isActive );
		(*iter)->SetControllable( isControllable );
		++camIdx;
	}
}


//remember to write a *CORRECT* destructor
