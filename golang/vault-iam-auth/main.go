package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sts"
	"io/ioutil"
	"net/http"
	"os"
)

// This method is a stripped down version of Vault CLI's code
// https://github.com/hashicorp/vault/blob/master/builtin/credential/aws/cli.go#L38
func GenerateLoginData(configuredRegion string) (map[string]interface{}, error) {
	loginData := make(map[string]interface{})
	s, _ := session.NewSession(&aws.Config{
		Region: aws.String(configuredRegion),
	})
	svc := sts.New(s)

	var params *sts.GetCallerIdentityInput
	stsRequest, _ := svc.GetCallerIdentityRequest(params)
	stsRequest.Sign()

	headersJson, err := json.Marshal(stsRequest.HTTPRequest.Header)
	if err != nil {
		return nil, err
	}

	requestBody, err := ioutil.ReadAll(stsRequest.HTTPRequest.Body)
	if err != nil {
		return nil, err
	}

	loginData["iam_http_request_method"] = stsRequest.HTTPRequest.Method
	loginData["iam_request_url"] = base64.StdEncoding.EncodeToString([]byte(stsRequest.HTTPRequest.URL.String()))
	loginData["iam_request_headers"] = base64.StdEncoding.EncodeToString(headersJson)
	loginData["iam_request_body"] = base64.StdEncoding.EncodeToString(requestBody)

	return loginData, nil
}

func VaultLogin(role string, loginData map[string]interface{}) {
	var vaultAddr = os.Getenv("VAULT_ADDR")
	//TODO: Make configurable
	awsAuthPath := "auth/aws"
	path := vaultAddr + "/v1/" + awsAuthPath + "/login"
	loginData["role"] = role

	jsonStr, _ := json.Marshal(loginData)
	request, _ := http.NewRequest("POST", path, bytes.NewBuffer(jsonStr))
	request.Header.Set("Content-Type", "application/json")
	client := &http.Client{}
	response, err := client.Do(request)
	if err != nil {
		panic(err)
	}
	defer response.Body.Close()

	body, _ := ioutil.ReadAll(response.Body)
	fmt.Println(string(body))
}

func main() {
	region := os.Args[1]
	role := os.Args[2]
	loginData, _ := GenerateLoginData(region)
	VaultLogin(role, loginData)
}
