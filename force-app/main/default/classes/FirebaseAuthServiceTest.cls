@IsTest
private class FirebaseAuthServiceTest {

    /**
     * Mock for successful Firebase OAuth token response.
     */
    private class FirebaseAuthSuccessMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            System.assertEquals(
                'POST',
                req.getMethod(),
                'OAuth request should use POST'
            );

            System.assertEquals(
                'https://oauth2.googleapis.com/token',
                req.getEndpoint(),
                'Unexpected OAuth endpoint'
            );

            System.assertEquals(
                'application/x-www-form-urlencoded',
                req.getHeader('Content-Type'),
                'Unexpected Content-Type'
            );

            System.assertNotEquals(
                null,
                req.getBody(),
                'Request body should not be null'
            );

            System.assert(
                req.getBody().contains('grant_type='),
                'Request body should contain grant_type'
            );

            System.assert(
                req.getBody().contains('assertion='),
                'Request body should contain JWT assertion'
            );

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setHeader('Content-Type', 'application/json');

            response.setBody(
                JSON.serialize(
                    new Map<String, Object>{
                        'access_token' => 'mock_firebase_access_token',
                        'expires_in'   => 3600,
                        'token_type'   => 'Bearer'
                    }
                )
            );

            return response;
        }
    }

    /**
     * Mock for failed Firebase OAuth response.
     */
    private class FirebaseAuthFailureMock implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(400);
            response.setStatus('Bad Request');
            response.setHeader('Content-Type', 'application/json');

            response.setBody(
                JSON.serialize(
                    new Map<String, Object>{
                        'error' => 'invalid_grant',
                        'error_description' => 'Invalid JWT Signature'
                    }
                )
            );

            return response;
        }
    }

    /**
     * Tests successful Firebase access token generation.
     */
    @IsTest
    static void testGetAccessTokenSuccess() {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseAuthSuccessMock()
        );

        Test.startTest();

        String accessToken = FirebaseAuthService.getAccessToken();

        Test.stopTest();

        System.assertNotEquals(
            null,
            accessToken,
            'Access token should not be null'
        );

        System.assertEquals(
            'mock_firebase_access_token',
            accessToken,
            'Returned access token does not match mock token'
        );
    }

    /**
     * Tests Firebase OAuth failure.
     */
    @IsTest
    static void testGetAccessTokenFailure() {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseAuthFailureMock()
        );

        Boolean exceptionThrown = false;

        Test.startTest();

        try {

            FirebaseAuthService.getAccessToken();

        } catch (FirebaseAuthService.FirebaseAuthException ex) {

            exceptionThrown = true;

            System.assert(
                ex.getMessage().contains(
                    'Failed to get Firebase access token'
                ),
                'Unexpected exception message: ' + ex.getMessage()
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'FirebaseAuthException should be thrown for failed OAuth request'
        );
    }

    /**
     * Tests malformed/success response without access_token.
     *
     * Your current FirebaseAuthService simply returns null in this scenario,
     * so this test documents that current behavior.
     */
    @IsTest
    static void testSuccessfulResponseWithoutAccessToken() {

        Test.setMock(
            HttpCalloutMock.class,
            new FirebaseAuthMissingTokenMock()
        );

        Test.startTest();

        String accessToken = FirebaseAuthService.getAccessToken();

        Test.stopTest();

        System.assertEquals(
            null,
            accessToken,
            'Token should be null when access_token is missing'
        );
    }

    /**
     * Mock returning HTTP 200 but without access_token.
     */
    private class FirebaseAuthMissingTokenMock
        implements HttpCalloutMock {

        public HTTPResponse respond(HTTPRequest req) {

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setHeader(
                'Content-Type',
                'application/json'
            );

            response.setBody(
                JSON.serialize(
                    new Map<String, Object>{
                        'expires_in' => 3600,
                        'token_type' => 'Bearer'
                    }
                )
            );

            return response;
        }
    }
}