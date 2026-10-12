import {File,Paths} from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import {adminWorkbook} from './admin-workbook';
import type {AdminReport} from './admin-statistics';
export async function shareAdminExcel(report:AdminReport){if(!await Sharing.isAvailableAsync())throw Error('Este dispositivo no permite compartir archivos.');const file=new File(Paths.cache,`Pulso-estadisticas-${report.start}-${report.end}-${Date.now()}.xlsx`);file.create();try{file.write(adminWorkbook(report));await Sharing.shareAsync(file.uri,{mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',UTI:'org.openxmlformats.spreadsheetml.sheet',dialogTitle:'Guardar estadísticas de Pulso'})}catch(e){if(file.exists)file.delete();throw e}}
