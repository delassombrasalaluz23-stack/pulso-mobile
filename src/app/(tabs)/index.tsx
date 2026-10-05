import {useAuth} from '../../lib/auth';
import OwnerHome from '../../components/owner-home';
import ClientHome from '../../components/client-home';
export default function Home(){const {profile}=useAuth();return profile?.role==='owner'?<OwnerHome/>:<ClientHome/>}
