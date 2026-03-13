import { LightningElement } from 'lwc';
import contactUs from '@salesforce/resourceUrl/ContactUs';

export default class ContactUs extends LightningElement {
  // builds inline style binding for background image so static resource loads correctly
  get bgStyle() {
    // background-size/position are in CSS; we set only image here
    return `background-image: url(${contactUs});`;
  }
}