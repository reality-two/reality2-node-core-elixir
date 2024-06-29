using UnityEngine;
using UnityEngine.Networking;
using System.Collections;
using System.Security.Cryptography.X509Certificates;

public class MyBehavior : MonoBehaviour
{
    void Start()
    {
        StartCoroutine(Upload());
    }

    IEnumerator Upload()
    {
        var vars = new Hashtable();
        var query = new gql { query = "query { sentantAll { id name } }", variables = vars };
        string json = JsonUtility.ToJson(query);

        Debug.Log(json);

        using (UnityWebRequest www = UnityWebRequest.Post("https://localhost:4005/reality2", json, "application/json"))
        {
            www.certificateHandler = new AcceptAllCertificates();

            yield return www.SendWebRequest();

            if (www.result != UnityWebRequest.Result.Success)
            {
                Debug.LogError(www.error);
            }
            else
            {
                Debug.Log("Response: " + www.downloadHandler.text);
            }
        }
    }

    public class AcceptAllCertificates : CertificateHandler
    {
        protected override bool ValidateCertificate(byte[] certificateData)
        {
            // Accept all certificates
            return true;
        }
    }

    [System.Serializable]
    public class gql
    {
        public string query;
        public object variables;
    }
}