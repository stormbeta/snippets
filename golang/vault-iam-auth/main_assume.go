package main

// Alternate version that allows assuming a role first

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/credentials/stscreds"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sts"
	"io/ioutil"
	"net/http"
	"os"
)

// Originally based on Vault CLI's own code
// https://github.com/hashicorp/vault/blob/master/builtin/credential/aws/cli.go#L38
func GenerateLoginData(configuredRegion string, roleArn string) (map[string]interface{}, error) {
	loginData := make(map[string]interface{})
	// TODO: Is region really needed?
	s, _ := session.NewSession(&aws.Config{
		Region: aws.String(configuredRegion),
	})

	// Assume IAM Role
	creds := stscreds.NewCredentials(s, roleArn, func(provider *stscreds.AssumeRoleProvider) {
		provider.RoleSessionName = os.Getenv("USER")
	})

	svc := sts.New(s, &aws.Config{Credentials: creds})

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

type VaultAuth struct {
	ClientToken   string            `json:"client_token"`
	LeaseDuration int               `json:"lease_duration"`
	TokenPolicies []string          `json:"token_policies"`
	Policies      []string          `json:"policies"`
	Metadata      map[string]string `json:"metadata"`
	Accessor      string            `json:"accessor"`
	Renewable     bool              `json:"renewable"`
}

type VaultResponse struct {
	Auth     VaultAuth `json:"auth"`
	Warnings []string  `json:"warnings"`
}

type VaultError struct {
	Errors []string `json:"errors"`
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
	if response.StatusCode >= 400 {
		var errors VaultError
		json.Unmarshal(body, &errors)
		fmt.Println(errors)
		os.Exit(1)
	} else {
		var data VaultResponse
		json.Unmarshal(body, &data)
		fmt.Println(data.Auth.ClientToken)
		os.Exit(0)
	}
}

func main() {
	region := os.Args[1]
	role := os.Args[2]
	loginData, _ := GenerateLoginData(region, "ROLE_ARN")
	VaultLogin(role, loginData)
}
