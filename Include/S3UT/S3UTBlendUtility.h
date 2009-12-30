#ifndef BLEND_UTIL
#define BLEND_UTIL

class BlendingUtility
{
public:
	FLOAT			  OriginalBlendFactor[4];
	UINT		      OriginalSampleMask;
	ID3D10BlendState* pOriginalBlendState;

	ID3D10BlendState* m_pSceneBlendStateInitial;
	ID3D10BlendState* m_pSceneBlendStateOn;

	HRESULT OnD3D10CreateDevice(ID3D10Device *pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void *pUserContext);
	void OnD3D10DestroyDevice( void* pUserContext );

};

HRESULT BlendingUtility::OnD3D10CreateDevice(ID3D10Device *pDev10, const DXGI_SURFACE_DESC *pBackBufferSurfaceDesc, void *pUserContext)
{
	SAFE_RELEASE(m_pSceneBlendStateInitial);
	SAFE_RELEASE(m_pSceneBlendStateOn);
	SAFE_RELEASE(pOriginalBlendState);
	D3D10_BLEND_DESC StateDesc;
	ZeroMemory( &StateDesc, sizeof(D3D10_BLEND_DESC) );
	StateDesc.AlphaToCoverageEnable = FALSE;
	StateDesc.BlendEnable[0] = TRUE;
	StateDesc.SrcBlend = D3D10_BLEND_SRC_ALPHA;
	StateDesc.DestBlend = D3D10_BLEND_ZERO;
	StateDesc.BlendOp = D3D10_BLEND_OP_ADD;
	StateDesc.SrcBlendAlpha = D3D10_BLEND_ZERO;
	StateDesc.DestBlendAlpha = D3D10_BLEND_ZERO;
	StateDesc.BlendOpAlpha = D3D10_BLEND_OP_ADD;
	StateDesc.RenderTargetWriteMask[0] = 0xf;
	pDev10->CreateBlendState( &StateDesc, &m_pSceneBlendStateInitial );
	StateDesc.DestBlend = D3D10_BLEND_ONE;
	pDev10->CreateBlendState( &StateDesc, &m_pSceneBlendStateOn );

	OriginalSampleMask = 0;
	pDev10->OMGetBlendState( &pOriginalBlendState, OriginalBlendFactor, &OriginalSampleMask );

	return S_OK;

}

void BlendingUtility::OnD3D10DestroyDevice( void* pUserContext )
{
	SAFE_RELEASE(m_pSceneBlendStateInitial);
	SAFE_RELEASE(m_pSceneBlendStateOn);
	SAFE_RELEASE(pOriginalBlendState);
}


//void REFERENCE::OnD3D10FrameRender(CDXUTDialog &g_SampleUI,NVUTMesh &g_MeshScene,float g_fFilterSize,float g_LightNumberPerRow,
//									  SSMap &ssmap,NVUTCamera &g_CameraRef,NVUTCamera &g_LCameraRef, 
//									  ID3D10Device* pDev10, double fTime, float fElapsedTime, void* pUserContext)
//{
//
//	for (int iRow = 0; iRow < g_LightNumberPerRow; iRow++ )
//		for (int iColumn = 0; iColumn < g_LightNumberPerRow; iColumn++ )
//		{
//			//int i = iRow*smarray->m_iSamplesPerRow + iColumn;
//			D3DXMATRIX mTrans,LightView,mLightViewProj;
//			D3DXMatrixTranslation(&mTrans,fStartPt+iRow*fInterval,fStartPt+iColumn*fInterval,0);
//
//			if(g_LightNumberPerRow > 1)
//				D3DXMatrixMultiply(&LightView, &mLightView,&mTrans);
//			else
//				LightView = mLightView;
//
//			D3DXMatrixMultiply(&mLightViewProj,&LightView,&ssmap.mLightProj);
//			V(m_pEffect->GetVariableByName("mLightViewProj")->AsMatrix()->SetMatrix((float *)&mLightViewProj));
//
//			/************************************************************************/
//			/*                    render      depth                                 */
//			/************************************************************************/
//			pDev10->RSSetState(m_pSMRenderState);
//			pDev10->OMSetDepthStencilState(m_pSMDSState, 0);
//			pDev10->RSSetViewports(1, &vp);
//			ID3D10RenderTargetView *pNullRTView = NULL;
//			pDev10->IASetInputLayout(m_DepthLayout);
//			pDev10->OMSetRenderTargets(1, &pNullRTView, m_pDepthDSView);			
//			pDev10->ClearDepthStencilView(m_pDepthDSView, D3D10_CLEAR_DEPTH, 1.0, 0);
//
//
//			/************************************************************************/
//			/*                                                                      */
//			/************************************************************************/
//
//			g_MeshScene.Render( MAX_BONE_MATRICES,
//								(FLOAT)SCALE,
//								m_pEffect,
//								m_pEffect->GetTechniqueByName(SUIT_TECH_NAME),
//								m_pEffect->GetTechniqueByName(BODY_TECH_NAME),
//								m_pEffect->GetTechniqueByName("RenderDepth"),
//								m_pEffect->GetTechniqueByName("RenderDepth"),
//								&mLightViewProj,
//								pDev10,
//								fTime,fElapsedTime,pUserContext, true);
//
//			//**********************************************************************/
//			/*                      render vp                                      */
//			//**********************************************************************/
//			V(ssmap.m_pOldRenderState->Apply());
//
//			pDev10->OMSetRenderTargets(1,&m_pREFRTView,DXUTGetD3D10DepthStencilView());
//			pDev10->RSSetState(m_pRenderState);
//
//			// do a z-only(PS-null) pass from eye camera and fill default z-buffer
//			//pDev10->IASetInputLayout(m_DepthLayout);
//			//g_MeshScene.Render( MAX_BONE_MATRICES,
//			//					(FLOAT)SCALE,
//			//					m_pEffect,
//			//					m_pEffect->GetTechniqueByName(SUIT_TECH_NAME),
//			//					m_pEffect->GetTechniqueByName(BODY_TECH_NAME),
//			//					m_pEffect->GetTechniqueByName("RenderMultiDepth"),
//			//					m_pEffect->GetTechniqueByName("RenderMultiDepth"),
//			//					&mLightViewProj,
//			//					pDev10,
//			//					fTime,fElapsedTime,pUserContext, true);
//
//			pDev10->IASetInputLayout(m_pMaxLayout);
//
//			//float fComponent = (float)1.0/(float)iNumLights;
//			float NewBlendFactor[4] = {0,0,0,0};
//
//			//alpha blending initial;
//			if( iRow == 0 && iColumn == 0 )
//			{		
//				pDev10->OMSetBlendState( m_pSceneBlendStateInitial, NewBlendFactor, 0xffffffff );					
//			}		
//			else
//			{
//				pDev10->OMSetBlendState( m_pSceneBlendStateOn, NewBlendFactor, 0xffffffff );											
//			}
//
//			V(m_pEffect->GetVariableByName("DepthTex0")->AsShaderResource()->SetResource(m_pDepthSRView));
//			V(m_pEffect->GetVariableByName("LightNumber")->AsScalar()->SetFloat(g_LightNumberPerRow));
//
//			g_MeshScene.Render( MAX_BONE_MATRICES,
//								(FLOAT)SCALE,
//								m_pEffect,
//								m_pEffect->GetTechniqueByName("SceneMultiOcc"),
//								m_pEffect->GetTechniqueByName("SkinnedMultiOcc"),
//								m_pEffect->GetTechniqueByName("RenderMultiOcc"),
//								m_pEffect->GetTechniqueByName("RenderMultiOcc"),
//								&mWorldViewProj,
//								pDev10,
//								fTime,fElapsedTime,pUserContext, true);
//			
//
//			//alpha blending restore			
//			pDev10->OMSetBlendState( pOriginalBlendState, OriginalBlendFactor, OriginalSampleMask );
//		}
//			
//
//}
//*/

#endif