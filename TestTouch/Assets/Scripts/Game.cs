using UnityEngine;

public class Game : MonoBehaviour
{

	private GameObject targetObj;
	private GameObject previweObj;

	// Use this for initialization
	void Start ()
	{
	}
	
	// Update is called once per frame
	void Update () {
		if( Input.GetMouseButtonDown( 0 ) )
		{
			targetObj = GetTouchedObject( Input.mousePosition );
			if( targetObj != null )
			{
				previweObj = CloneObject( targetObj );
			}
		}

		if( Input.GetMouseButton( 0 ) )
		{
			if( previweObj != null )
			{
				UpdatePreview( Input.mousePosition );
			}
		}
		
		if( Input.GetMouseButtonUp( 0 ) )
		{
			if( previweObj != null )
			{
				Destroy( previweObj );
				previweObj = null;
			}
		}
	}

	private GameObject GetTouchedObject( Vector2 point )
	{
		RaycastHit hit;
		var ray = Camera.main.ScreenPointToRay( point );
		var success = Physics.Raycast( ray, out hit, float.MaxValue );
		if( success )
		{
			return hit.collider.gameObject;
		}
		return null;
	}

	private GameObject CloneObject( GameObject obj )
	{
		var preview = Instantiate( obj );
		preview.gameObject.name = "preview_" + obj.gameObject.name;
		preview.layer = LayerMask.NameToLayer( "DragObject" );
		return preview;
	}

	private void UpdatePreview( Vector2 point )
	{
		var distance = Vector3.Distance( targetObj.transform.position, Camera.main.transform.position );
		var pos = new Vector3(point.x, point.y, Camera.main.nearClipPlane);
		var posInView = Camera.main.ScreenToViewportPoint( pos );
		posInView.z = distance;
		previweObj.transform.position = Camera.main.ViewportToWorldPoint( posInView );
	}
}
