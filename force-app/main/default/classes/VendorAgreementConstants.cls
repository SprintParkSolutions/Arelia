/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : VendorAgreementConstants
 * Author          : <YourName>
 * Created Date    : Jun 26, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 26, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 26, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public inherited sharing class VendorAgreementConstants {

    public static final String ARELIA_RECORD_TYPE_DEVELOPER_NAME = 'Arelia';

    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_SENT = 'Sent';
    public static final String STATUS_SIGNED = 'Signed';

    public static final Integer TOKEN_EXPIRY_DAYS = 14;

    public static final String UNSIGNED_FILE_PREFIX =
        'Vendor Agreement - ';

    public static final String SIGNED_FILE_PREFIX =
        'Signed Vendor Agreement - ';

    public static final String PDF_EXTENSION = '.pdf';

    @TestVisible
    private VendorAgreementConstants() {
    }
}