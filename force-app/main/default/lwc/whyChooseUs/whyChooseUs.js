import { LightningElement, api } from 'lwc';
// Use the exact static resource name you created in Salesforce
import ASSET_URL from '@salesforce/resourceUrl/WHY_ASSETS';

export default class WhyChooseUs extends LightningElement {
  /** Optional override from parent or CMS */
  @api imageUrl;        // if you want to override with an external URL
  @api imgAlt = 'Decorative marble texture';

  // For single-file static resource use the imported ASSET_URL directly
  defaultImg = ASSET_URL;

  get imgSrc() {
    return (this.imageUrl && this.imageUrl.trim().length) ? this.imageUrl : this.defaultImg;
  }
}