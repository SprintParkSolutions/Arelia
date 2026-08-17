/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementTokenServiceTest
 * Author          : <YourName>
 * Created Date    : Jun 29, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 29, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 29, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

/**
 * Test class for ClientAgreementTokenService.
 */
@IsTest
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveAsserts')
private class ClientAgreementTokenServiceTest {

    private static final Integer SHA_256_HEX_LENGTH = 64;
    private static final Integer DEFAULT_EXPIRY_DAYS = 7;
    private static final Integer EXPIRY_TOLERANCE_SECONDS = 10;

    @IsTest
    static void generateTokenShouldReturnValidSha256HexToken() {
        Test.startTest();
        String tokenValue = ClientAgreementTokenService.generateToken();
        Test.stopTest();

        System.assertNotEquals(null, tokenValue, 'Token should not be null.');
        System.assertEquals(
            SHA_256_HEX_LENGTH,
            tokenValue.length(),
            'SHA-256 hex token should be 64 characters.'
        );
        System.assert(
            Pattern.matches('^[a-fA-F0-9]{64}$', tokenValue),
            'Token should contain only hexadecimal characters.'
        );
    }

    @IsTest
    static void generateTokenShouldReturnDifferentValuesAcrossCalls() {
        Test.startTest();
        String firstToken = ClientAgreementTokenService.generateToken();
        String secondToken = ClientAgreementTokenService.generateToken();
        String thirdToken = ClientAgreementTokenService.generateToken();
        Test.stopTest();

        Set<String> tokenValues = new Set<String>{
            firstToken,
            secondToken,
            thirdToken
        };

        System.assertEquals(
            3,
            tokenValues.size(),
            'Generated tokens should be unique across multiple calls.'
        );
    }

    @IsTest
    static void getDefaultExpiryShouldReturnDateSevenDaysFromNow() {
        Datetime beforeCall = System.now().addDays(DEFAULT_EXPIRY_DAYS);

        Test.startTest();
        Datetime expiryDate = ClientAgreementTokenService.getDefaultExpiry();
        Test.stopTest();

        Datetime afterCall = System.now().addDays(DEFAULT_EXPIRY_DAYS);

        System.assertNotEquals(null, expiryDate, 'Expiry date should not be null.');
        System.assert(
            expiryDate >= beforeCall.addSeconds(-EXPIRY_TOLERANCE_SECONDS),
            'Expiry date should be around seven days from now.'
        );
        System.assert(
            expiryDate <= afterCall.addSeconds(EXPIRY_TOLERANCE_SECONDS),
            'Expiry date should be around seven days from now.'
        );
    }
}