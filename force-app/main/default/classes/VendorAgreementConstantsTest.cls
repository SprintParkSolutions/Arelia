/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementConstantsTest
 * Author          : <YourName>
 * Created Date    : Jul 14, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jul 14, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jul 14, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

/**
 * Test class for VendorAgreementConstants.
 *
 * @description
 * Validates all constant values used by the Vendor Agreement functionality.
 */
@IsTest
private class VendorAgreementConstantsTest {
    @IsTest
    static void shouldValidateRecordTypeConstant() {
        System.assertEquals(
            'Arelia',
            VendorAgreementConstants.ARELIA_RECORD_TYPE_DEVELOPER_NAME,
            'Arelia record type developer name should match.'
        );
    }

    @IsTest
    static void shouldValidateAgreementStatusConstants() {
        System.assertEquals(
            'Draft',
            VendorAgreementConstants.STATUS_DRAFT,
            'Draft status should match.'
        );

        System.assertEquals(
            'Sent',
            VendorAgreementConstants.STATUS_SENT,
            'Sent status should match.'
        );

        System.assertEquals(
            'Signed',
            VendorAgreementConstants.STATUS_SIGNED,
            'Signed status should match.'
        );
    }

    @IsTest
    static void shouldValidateTokenExpiryConstant() {
        System.assertEquals(
            14,
            VendorAgreementConstants.TOKEN_EXPIRY_DAYS,
            'Token expiry days should match.'
        );
    }

    @IsTest
    static void shouldValidateFileNameConstants() {
        System.assertEquals(
            'Vendor Agreement - ',
            VendorAgreementConstants.UNSIGNED_FILE_PREFIX,
            'Unsigned file prefix should match.'
        );

        System.assertEquals(
            'Signed Vendor Agreement - ',
            VendorAgreementConstants.SIGNED_FILE_PREFIX,
            'Signed file prefix should match.'
        );

        System.assertEquals(
            '.pdf',
            VendorAgreementConstants.PDF_EXTENSION,
            'PDF extension should match.'
        );
    }

    @IsTest
    static void shouldCoverPrivateConstructor() {
        VendorAgreementConstants constantsInstance =
            new VendorAgreementConstants();

        System.assertNotEquals(
            null,
            constantsInstance,
            'Constants instance should not be null.'
        );
    }
}