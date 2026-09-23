public with sharing class FirebaseAuthService {

    // 🔴 Replace these values from your NEW Firebase JSON
    private static final String PROJECT_ID = 'areliaspace-e5f22';
    private static final String CLIENT_EMAIL = 'firebase-adminsdk-fbsvc@areliaspace-e5f22.iam.gserviceaccount.com';
    private static final String TOKEN_URI = 'https://oauth2.googleapis.com/token';

    // 🔴 Paste NEW private_key here from JSON.
    // Keep \n exactly as it is from JSON.
    // Do not share this key with anyone.
    private static final String PRIVATE_KEY = '-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDNTHskDxzZOwnZ\nB+5L8GadtqGQqD4WbweFjiXpwPO3QAjhcWz+JbkhXBXTJZAjDAK2uAUdGK567M55\ncIOFvhHVr0LPLYAWESuXq0x3zc/7xuvwiP3vwMEUW0B20ZKHYyR7V6Yf6Q1CNRtf\nLHqxZ8y1UEXjxbzDdYvlmzn7KTe7d3bTkLtlILVIs4d7qYvNmaaFY4o1RasBPdW5\ndKXLRCvn0yz/7mfo1HUluZIP5jK32HgCCmZSEGZGGhnXaziMy3HcBva8WLvbmCvN\niYgn4C0eR1YAvqmli7rQrbRfMcD4WIKHyrwKhkhjV7GTrLkISSrvVYDD6z5B/gcc\no6ENwIXzAgMBAAECggEANgoyw9wiiN/siK94v46JRGyFfNF8fmU9gp9XRX+f55W4\ngLddrEx7vddCe3EAzujjcftghTcw/nSFKRw/0p2kji3zFRvyAl0Er4jMuSB45dqH\n0qoMxeZkLJqUjnI98ttbCAibVvz+m3XlPZk0tqwPC48Uxo8PUBgJ+idxDLbdz796\n11tDmfFW+1whrwLXtm10DKohLDmQf/Du2Jvtu/ylZ6eEsvU4IeV+5HHGD6QYQW48\nkdMKN+tmGj+Nk9yMgq38dYWYjYEwQddFUp1cfZTiIvmPklgZcnsbNyRVzUrkJoH/\nZEKQI4aEQlf2wCrhFsyU1+DN9n0doh2gPXhmi2432QKBgQDpKBDSvxM/9drPqzc8\n3ZwU+7M0xjnwwTUQ6WPj/IGKv2U+t0B1zMFfLeMdsG0ghU9kWOiPyFCunk9iWoED\nJBZdYZWIiMvAhhrpaH08ati/yxL6Dr4kajSo4QfDAd7UK/bZG5gVnvndfutfCF+N\nft0oOSEUW8YWNYCWmvTUjhH0LwKBgQDhabLiQ7XrfyvOEltTYqeQtH+tPDGpdXsC\nE/IX1bMZ8uOLkCJJrViZIyUcyGMvHLqF0lza3zOhT+LwEM4+vWPnmG7vsPcLdtsi\nC7uBwX1+/IPvvEmBWZrcxs0XQYEGgno85V1lu4KRMhdGTKdVF8EqjLA/mfIx7bkx\nmX21dIalfQKBgQDBfSlw63bbJnl+y5TcowArfbH7guGEhaI3NahbBCqw7SLlSAhr\neg+joB4Rfl8hlOAM46ej4tXqA6DXe0oDREh3GEuS8gs8602cE8WShQz5JVrLP77V\n03l+CLl7QKseIpoJFFhC4Rp0kSZdSEKb1wNLpRVporuhpKbg1RmG55vIqwKBgQCK\nBc+r7iv5fBAViXX0NAdIes1nBOGf0ri0SARIBek57VjZPzNPi94hPrzdx/G7ikrH\n4ExNFLingKQDvTacghknWVYsXF6Y3XlGeoqg5Bp05CfhZphXpMdHgk9YexqHIuO4\nX/V1coB7aYGI4Szg1L/JzwWonBoJ6ncoYMTxk91SfQKBgQCnbvG1k2CekB1pMTDw\nQvjkf3YBhhI+pRQHwcU6oMgELlwNrmiMXHaicrSdlN7YjhgBXnRD/RWr/nm0yky6\nsK6iFXkWW4yku0JjnrVFkfIzgaM7RrhEuO8wBxz9nn42p4tz24Wb/gOxU0a13/kF\n6RxLlNJYIhgQl3oewQ8y11/zTQ==\n-----END PRIVATE KEY-----\n';

    public static String getAccessToken() {
        Long nowSeconds = DateTime.now().getTime() / 1000;
        Long expSeconds = nowSeconds + 3600;

        Map<String, Object> header = new Map<String, Object>{
            'alg' => 'RS256',
            'typ' => 'JWT'
        };

        Map<String, Object> claims = new Map<String, Object>{
            'iss' => CLIENT_EMAIL,
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => TOKEN_URI,
            'iat' => nowSeconds,
            'exp' => expSeconds
        };

        String encodedHeader = base64UrlEncode(Blob.valueOf(JSON.serialize(header)));
        String encodedClaims = base64UrlEncode(Blob.valueOf(JSON.serialize(claims)));

        String unsignedJwt = encodedHeader + '.' + encodedClaims;

        Blob privateKeyBlob = getPrivateKeyBlob();
        Blob signature = Crypto.sign(
            'RSA-SHA256',
            Blob.valueOf(unsignedJwt),
            privateKeyBlob
        );

        String jwt = unsignedJwt + '.' + base64UrlEncode(signature);

        HttpRequest req = new HttpRequest();
        req.setEndpoint(TOKEN_URI);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        String body =
            'grant_type=' + EncodingUtil.urlEncode('urn:ietf:params:oauth:grant-type:jwt-bearer', 'UTF-8') +
            '&assertion=' + EncodingUtil.urlEncode(jwt, 'UTF-8');

        req.setBody(body);
        req.setTimeout(120000);

        Http http = new Http();
        HttpResponse res = http.send(req);

        System.debug('Firebase OAuth Status: ' + res.getStatusCode());
        System.debug('Firebase OAuth Body: ' + res.getBody());

        if (res.getStatusCode() != 200) {
            throw new FirebaseAuthException('Failed to get Firebase access token: ' + res.getBody());
        }

        Map<String, Object> result =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        return (String) result.get('access_token');
    }

    private static Blob getPrivateKeyBlob() {
        String key = PRIVATE_KEY;

        key = key.replace('-----BEGIN PRIVATE KEY-----', '');
        key = key.replace('-----END PRIVATE KEY-----', '');
        key = key.replace('\\n', '');
        key = key.replace('\n', '');
        key = key.replace('\r', '');
        key = key.replace(' ', '');

        return EncodingUtil.base64Decode(key);
    }

    private static String base64UrlEncode(Blob input) {
        String output = EncodingUtil.base64Encode(input);
        output = output.replace('+', '-');
        output = output.replace('/', '_');
        output = output.replace('=', '');
        return output;
    }

    public class FirebaseAuthException extends Exception {}
}