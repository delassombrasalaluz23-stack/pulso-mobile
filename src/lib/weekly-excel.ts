import {File,Paths} from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import {weeklyWorkbook} from './weekly-workbook';
import type {WeekReport} from './weekly-stats';
export async function shareWeeklyExcel(report:WeekReport){if(!await Sharing.isAvailableAsync())throw Error('Este dispositivo no permite compartir archivos.');const file=new File(Paths.cache,`Pulso-semana-${report.start}-${Date.now()}.xlsx`);file.create();try{file.write(weeklyWorkbook(report));await Sharing.shareAsync(file.uri,{mimeType:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',UTI:'org.openxmlformats.spreadsheetml.sheet',dialogTitle:'Guardar o compartir reporte semanal'})}catch(e){if(file.exists)file.delete();throw e}}
