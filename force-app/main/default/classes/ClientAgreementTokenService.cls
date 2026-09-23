/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementTokenService
 * Author          : <YourName>
 * Created Date    : Jun 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 10, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 10, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class ClientAgreementTokenService {

    public static String generateToken() {
        Blob randomBlob = Crypto.generateAesKey(256);
        String randomString = EncodingUtil.convertToHex(randomBlob);

        Blob digest = Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(randomString + String.valueOf(System.now().getTime()))
        );

        return EncodingUtil.convertToHex(digest);
    }

    public static Datetime getDefaultExpiry() {
        return System.now().addDays(7);
    }
}