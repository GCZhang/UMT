#include <stdio.h>

#define WARP_SIZE 32

#define GROUPSET 16
#define NUMFACES 3

#define fouralpha 1.82
#define fouralpha4 5.82


#define Connect(a,b,c) Connect[ a + 3 * ( b + mC * c ) ]

__device__ __forceinline__ double shfl_d(double var,int lane)
{ float lo, hi;
  asm volatile("mov.b64 {%0,%1}, %2;" : "=f"(lo), "=f"(hi) : "d"(var));
  hi = __shfl(hi, lane);
  lo = __shfl(lo, lane);
  asm volatile("mov.b64 %0, {%1,%2};" : "=d"(var) : "f"(lo), "f"(hi));
  return var;
}


extern "C"
{


  __global__ void GPU_sweep(
			    int  size_maxCorner,
			    int  size_maxcf,
			    int  nAngle,
			    int  nzones,
			    int  ncornr,
			    int  Groups,
			    int  nbelem,
			    int* AngleOrder,
			    double* soa_omega,
			    int* nextZ,
			    int* next,
			    int* soa_nCorner,
			    int* soa_nCFaces,
			    int* soa_c0,
			    double* soa_STotal,
			    double* soa_STime,
			    double* soa_SigtInv,
			    double* soa_Volume,
			    double* soa_Sigt,
			    double* soa_A_fp,
			    double* soa_A_ez,
			    int* soa_Connect,
			    double* psic,
			    double* psib,
			    double* omega_A_fp,
			    double* omega_A_ez,
			    int* soa_Connect_ro,
			    int* passZ)
  {

    //   double omega[3];
    int c,ig,i,icface,ifp,cez,k;
    //   double Q[Groups * size_maxCorner];
    //   double src[Groups * size_maxCorner];
    //   double SigtVol[Groups * size_maxCorner];
    //   double afpm[size_maxcf];
    //   double psifp[Groups * size_maxcf];
    //   int    ez_exit[size_maxcf];
    //   double coefpsic[size_maxcf];
    //   double tpsic[Groups * size_maxCorner];
    //   double psi_opp[Groups];
    double area_opp,area_inv,sumArea;
    double r_psifp;

    double psi_opp,tpsic,r_afpm;
    double Q[8];
    double src[8];

    //double volume[8];
    //double coefpsic_stk[3];
    //double psifp[3];
    //int ez_exit[3];
  
    //double *src;
    volatile double *volume;
    volatile double *coefpsic;
    volatile double *psifp;
    volatile int *ez_exit;
    __shared__ volatile double sm_agg[12*128];  // 4x32 thread per tb. 8tb. 6KB
   
    int offset = (8+3+96+3)*threadIdx.y;
    volume = &(sm_agg[offset]);  //8 doubles  
    offset += size_maxCorner;

    coefpsic = &(sm_agg[offset]); // 3 doubles
    offset += size_maxcf;

    psifp = &(sm_agg[offset]); // 3 x 32 doubles
    offset += size_maxcf * WARP_SIZE;

    //note ez_exit has integer type
    ez_exit = (int*) &(sm_agg[offset]); // 3 int
    //   for(int Angle=0;Angle<nAngle;Angle++)

    //   const double fouralpha = 1.82;
    //   const double fouralpha4 = 5.82;
   
#define soa_omega(a,b) soa_omega[a + 3 * b]

    //   #define tpsic(ig,c) tpsic[ (ig) + Groups * (c)]
#define EB_ListExit(a,ia) EB_ListExit[ a + 2 * (ia) ]
#define soa_A_fp(a,icface,c,zone) soa_A_fp[ a + 3 * ( icface + size_maxcf * ( c + size_maxCorner * (zone) ) )]
#define soa_A_ez(a,icface,c,zone) soa_A_ez[ a + 3 * ( icface + size_maxcf * ( c + size_maxCorner * (zone) ) )]
#define omega_A_fp(icface,c,zone) omega_A_fp[ ( icface + size_maxcf * ( c + size_maxCorner * (zone) ) )]
#define omega_A_ez(icface,c,zone) omega_A_ez[ ( icface + size_maxcf * ( c + size_maxCorner * (zone) ) )]
#define soa_Connect(a,icface,c,zone) soa_Connect[ a + 3 * ( icface + size_maxcf * ( c + size_maxCorner * (zone) ) )]
   
#define psifp(ig,jf) psifp[(ig) + WARP_SIZE * (jf)]
#define psib(ig,b,c) psib[(ig) + Groups * ((b) + nbelem * (c) )]
#define psic(ig,b,c) psic[(ig) + Groups * ((b) + ncornr *(c) )]
   
#define Q(ig,c) Q[(ig) + WARP_SIZE * (c)]
    //#define src(ig,c) src[(ig) + Groups * (c)]
#define src(ig,c) src[c]
    //  #define SigtVol(ig,c) SigtVol[(ig) + Groups * (c)]
#define soa_Sigt(ig,zone) soa_Sigt[(ig) + Groups * (zone)]
#define soa_Volume(c,zone) soa_Volume[c + size_maxCorner * (zone)]
#define soa_SigtInv(ig,zone) soa_SigtInv[(ig) + Groups * (zone)]
#define soa_STotal(ig,c,zone) soa_STotal[ig + Groups * ( c + size_maxCorner * (zone) )]
//#define soa_STime(ig,c,Angle,zone) soa_STime[ig + Groups * ( c + size_maxCorner * ( Angle + nAngle * (zone) ) )]
#define soa_STime(ig,ic,Angle) soa_STime[ig + Groups * ( (ic) + ncornr * (Angle) ) ]
#define nextZ(a,b) nextZ[ (a) + nzones * (b) ]
#define next(a,b) next[ (a) + (ncornr+1)  * (b) ]

    //int mm = blockIdx.x;
    int Angle = AngleOrder[blockIdx.x]-1;
    ig = threadIdx.x;
 

    //   if(ig==0) printf("my offset=%d\n",offset);
    //   if(ig==0)
    //   {
    //     printf("psic=%x\n",psic);
    //     printf("nextZ=%x\n",psic);
    //     printf("next=%x\n",psic);
    //     printf("psib=%x\n",psic);
    //   }


    omega_A_fp += Angle * nzones * size_maxcf * size_maxCorner;
    omega_A_ez += Angle * nzones * size_maxcf * size_maxCorner;
    passZ      += Angle * nzones;
   
    const int group_offset=blockIdx.y * 32;

    //  if (!( group_offset + threadIdx.x < Groups )) return;
    
    psib += group_offset;
    psic += group_offset;
    soa_Sigt += group_offset;
    soa_STotal += group_offset;
    soa_SigtInv += group_offset;
    soa_STime += group_offset;

    int ndone = 0;
    int ndoneZ = 0;
    // hyperplane number p
    int p=0;

    while(ndoneZ < nzones)
    {
      //increment hyperplane
      p++;
      // get number of zones in this hyperplane
      int passZcnt = passZ[p] - passZ[p-1];

      for(int ii=threadIdx.y;ii<passZcnt;ii+=blockDim.y)
      {
	ndone = ( ndoneZ + ii ) * size_maxCorner;
 
	// get the zone (minus 1 so it is valid c index)
	int zone = nextZ(ndoneZ+ii,Angle) - 1;

	//       if(ig==0 && blockIdx.x==0) printf("ang=%d zone=%d tidy=%d ndoneZ=%d\n",blockIdx.x,zone,threadIdx.y,ndoneZ);
  
  
	int nCorner   = soa_nCorner[zone];
	int nCFaces   = soa_nCFaces[zone];
	int c0        = soa_c0[zone] ;
  
	double Sigt = soa_Sigt(ig,zone);
	double r_soa_SightInv = soa_SigtInv(ig,zone);
	double r_omega_A_fp;
	double r_omega_A_ez;
	int connect0,connect1,connect2;
  
	if(ig<nCorner) volume[ig] = soa_Volume(ig,zone);

	if(ig<nCorner*nCFaces)
	{
          int cc = size_maxcf * size_maxCorner;
          r_omega_A_fp = omega_A_fp[ig + cc * zone];
          r_omega_A_ez = omega_A_ez[ig + cc * zone];
          connect0     = soa_Connect_ro[ig + cc*(0 + 3*zone)];
          connect1     = soa_Connect_ro[ig + cc*(1 + 3*zone)];
          connect2     = soa_Connect_ro[ig + cc*(2 + 3*zone)];
	}
   
  
	for(c=0;c<nCorner;c++)
	{
	  double source = soa_STotal(ig,c,zone) + soa_STime(ig,c0+c,Angle);
	  Q[c]       = r_soa_SightInv *source ;
	  //src(ig,c)     = soa_Volume(c,zone) *source;
	  //volume[c] = soa_Volume(c,zone);
	  src(ig,c)     = volume[c]*source;
	  //SigtVol(ig,c) = soa_Sigt(ig,zone)*soa_Volume(c,zone);
	}
  
	for(i=0;i<nCorner;i++)
	{
  
	  int ic      = next(ndone+i,Angle);
	  c       = ic - c0 - 1;
  
	  sumArea = 0.0;
   
	  for(icface=0;icface<nCFaces;icface++)
	  {
	    //afpm[icface] = omega_A_fp(icface,c,zone);  
	    r_afpm = shfl_d(r_omega_A_fp,icface+size_maxcf*c);
  
	    //  if ( Angle == 1 && ig==0 && zone == 1 )
	    //    printf("a=%d,c=%d,icface=%d,afpm=%e\n",Angle,c,icface,r_afpm);
  
	    //       int icfp    = soa_Connect(0,icface,c,zone) - 1;
	    //       int ib      = soa_Connect(1,icface,c,zone) - 1;
	    int icfp= __shfl(connect0,icface+size_maxcf*c);
	    int ib= __shfl(connect1,icface+size_maxcf*c);
  
	    //         if ( Angle == 1 && ig==0 && zone == 1 )
	    //               printf("a=%d,c=%d,icface=%d,afpm=%e\n",Angle,c,icface,r_afpm);
                                                                                                     
	    if ( r_afpm >= 0.0 )
	    { 
	      sumArea = sumArea + r_afpm;
	    }
	    else
	    {
	      if (icfp == -1)
	      {
		//             psifp(ig,icface) = psib(ig,ib,Angle);
		r_psifp = psib(ig,ib,Angle);
		//    if ( Angle == 1 && ig==0 && zone == 0 )
		//      printf("a=%d,c=%d,icface=%d,zone=%d,icfp=%d,ib=%d,%e\n",Angle,c,icface,zone,icfp,ib,r_psifp);
	      }
	      else
	      {
		//             psifp(ig,icface) = psic(ig,icfp,Angle);
		//             printf("psic(%d,%d,%d)\n",ig,icfp,Angle);
		r_psifp = psic(ig,icfp,blockIdx.x);
		//          if ( Angle == 1 && ig==0 && zone == 0 )
		//            printf("a=%d,c=%d,icface=%d,zone=%d,icfp=%d,ib=%d,%e\n",Angle,c,icface,zone,icfp,ib,r_psifp);
            
	      }
  
	      src(ig,c)  -= r_afpm*r_psifp;
	      psifp(ig,icface) = r_psifp;
	      //psifp[icface] = r_psifp;
	    }
	    //       if ( Angle == 1 && ig==0 && zone == 1 )
	    //              printf("a=%d,c=%d,icface=%d,afpm=%e\n",Angle,c,icface,afpm[icface]);
	  }
  
  
	  //       if ( Angle == 1 && ig < 5 && c == 2 && zone == 1 )
	  //         printf("a=%d,g=%d,c=%d,psifp=%e,sumArea=%e\n",Angle,ig,c,psifp(ig,1),sumArea);
  
  
	  int nxez = 0;
  
	  for(icface=0;icface<nCFaces;icface++)
	  {
  
	    //double aez = omega_A_ez(icface,c,zone);
	    double aez = shfl_d(r_omega_A_ez,icface+size_maxcf*c);
	    //                     if ( Angle == 1 && ig==0 && zone == 0 )
	    //                            printf("a=%d,c=%d,aez=%e,icface=%d\n",Angle,c,aez,icface);
  
	    if (aez > 0.0 )
	    {
  
	      sumArea        = sumArea + aez;
	      area_opp       = .0;
	      //           cez            = soa_Connect(2,icface,c,zone) - 1;
	      cez            = __shfl(connect2,icface+size_maxcf*c);
	      ez_exit[nxez]  = cez;
	      coefpsic[nxez] = aez;
	      nxez           = nxez + 1;
  
	      if (nCFaces == 3)
	      {
  
		ifp = (icface+1)%nCFaces;
		r_afpm = shfl_d(r_omega_A_fp,ifp+size_maxcf*c);
                //       if ( Angle == 1 && ig==0 && zone == 1 )
                //         printf("a=%d,c=%d,ifp=%d,afpm=%e\n",Angle,c,ifp,afpm[ifp]);
  
		if ( r_afpm < 0.0 )
		{ 
		  area_opp   = -r_afpm;
		  psi_opp =  psifp(ig,ifp);
		  //psi_opp =  psifp[ifp];
		}
	      }
	      else
	      {
  
		ifp        = icface;
		area_opp   = 0.0;
		psi_opp = 0.0;
  
		for(k=0;k<nCFaces-2;k++)
		{
		  ifp = (ifp+1)%nCFaces;
		  r_afpm = shfl_d(r_omega_A_fp,ifp+size_maxcf*c);
		  if ( r_afpm < 0.0 )
		  {
		    area_opp   = area_opp   - r_afpm;
		    psi_opp = psi_opp - r_afpm*psifp(ig,ifp);
		    //psi_opp = psi_opp - r_afpm*psifp[ifp];
		  }
		}
  
		area_inv = 1.0/area_opp;
  
		psi_opp = psi_opp*area_inv;
  
	      }
  
	      if (area_opp > 0.0) {
  
		double aez2 = aez*aez;
  
		{
    
		  double sigv         = Sigt*volume[c];
		  double sigv2        = sigv*sigv;
		  double gnum         = aez2*( fouralpha*sigv2 +       aez*(4.0*sigv + 3.0*aez) );
		  double gtau         = gnum/( gnum + 4.0*sigv2*sigv2 + aez*sigv*(6.0*sigv2 + 2.0*aez*(2.0*sigv + aez)) ) ;
		  double sez          = gtau*sigv*( psi_opp - Q[c] ) +   0.5*aez*(1.0 - gtau)*( Q[c] - Q[cez] );
  
		  src(ig,c)    = src(ig,c)   + sez;
		  src(ig,cez)  = src(ig,cez) - sez;
  
		  //                       if ( Angle == 1 && ig < 5 && zone == 0 )
		  //                                    printf("a=%d,g=%d,c=%d,cez=%d,icface=%d,src(c)=%e,src(cez)=%e,sez=%e\n",Angle,ig,c,cez,icface,src(ig,c),src(ig,cez),sez);
  
		}
  
	      }
	      else
	      {
		double sez          = 0.5*aez*( Q[c] - Q[cez] );
		src(ig,c)    = src(ig,c)   + sez;
		src(ig,cez)  = src(ig,cez) - sez;
  
	      } 
	    }
	  }
  
	  //       printf("ckim angle,zone,corner,aez_cnt %d,%d,%d,%d\n",Angle,zone,c,aez_cnt);
  
  
	  tpsic = src(ig,c)/(sumArea + Sigt*volume[c]);
  
  
	  for(icface=0;icface<nxez;icface++)
	  {
	    int cez   = ez_exit[icface];
	    src(ig,cez) = src(ig,cez) + coefpsic[icface]*tpsic;
	  }
  
	  //hope that ther is no self referencing
	  psic(ig,c0+c,blockIdx.x) = tpsic;
	  //psibatch(ig,c0+c,mm)= tpsic;

	  //     if ( Angle == 1 && ig < 5 && zone == 0 )
	  //                  printf("a=%d,g=%d,c=%d,psic=%e,corner=%d\n",Angle,ig,c,tpsic,c0+c);
	} //end of corner 
  
      } //end of zone loop 
      ndoneZ += passZcnt;
      __syncthreads();
    } //end of while

  }


__global__ void GPU_fp_ez(
          int  size_maxCorner,
          int  size_maxcf,
          int  nAngle,
          int  nzones,
          int  ncornr,
          int  Groups,
          int  nbelem,
          int* AngleOrder,
       double* soa_omega,
          int* nextZ,
          int* next,
          int* soa_nCorner,
          int* soa_nCFaces,
          int* soa_c0,
       double* soa_A_fp,
       double* soa_A_ez,
       double* omega_A_fp,
       double* omega_A_ez,
          int* soa_Connect,
          int* soa_Connect_ro)
  {

//   double omega[3];
   int c,i,ig,icface,ii;
//   double Q[Groups * size_maxCorner];
//   double src[Groups * size_maxCorner];
//   double SigtVol[Groups * size_maxCorner];
//   double afpm[size_maxcf];
//   double psifp[Groups * size_maxcf];
//   int    ez_exit[size_maxcf];
//   double coefpsic[size_maxcf];
//   double tpsic[Groups * size_maxCorner];
//   double psi_opp[Groups];

   double omega0, omega1, omega2;
   

   
//   const double fouralpha4 = 5.82;
   
   #define soa_omega(a,b) soa_omega[a + 3 * b]
   #define omega_A_fp(icface,c,zone) omega_A_fp[  ( icface + size_maxcf * ( c + size_maxCorner * (zone) ) )]
   #define omega_A_ez(icface,c,zone) omega_A_ez[  ( icface + size_maxcf * ( c + size_maxCorner * (zone) ) )]

//   #define tpsic(ig,c) tpsic[ (ig) + Groups * (c)]
   #define EB_ListExit(a,ia) EB_ListExit[ a + 2 * (ia) ]
   #define soa_A_fp(a,icface,c,zone) soa_A_fp[ a + 3 * ( icface + size_maxcf * ( c + size_maxCorner * (zone) ) )]
   #define soa_A_ez(a,icface,c,zone) soa_A_ez[ a + 3 * ( icface + size_maxcf * ( c + size_maxCorner * (zone) ) )]
   #define soa_Connect(a,icface,c,zone) soa_Connect[ a + 3 * ( icface + size_maxcf * ( c + size_maxCorner * (zone) ) )]
   #define soa_Connect_ro(a,icface,c,zone) soa_Connect_ro[ icface + size_maxcf * ( c + size_maxCorner * ( a + 3 * zone) ) ]
   
   //#define psifp(ig,jf) psifp[(ig) + Groups * (jf)]
   #define psib(ig,b,c) psib[(ig) + Groups * ((b) + nbelem * (c) )]
   
     //#define Q(ig,c) Q[(ig) + Groups * (c)]
     //#define src(ig,c) src[(ig) + Groups * (c)]
//  #define SigtVol(ig,c) SigtVol[(ig) + Groups * (c)]
   #define soa_Sigt(ig,zone) soa_Sigt[(ig) + Groups * (zone)]
   #define soa_SigtInv(ig,zone) soa_SigtInv[(ig) + Groups * (zone)]
   #define soa_STotal(ig,c,zone) soa_STotal[ig + Groups * ( c + size_maxCorner * (zone) )]
//   #define soa_STime(ig,c,Angle,zone) soa_STime[ig + Groups * ( c + size_maxCorner * ( Angle + nAngle * (zone) ) )]
   #define nextZ(a,b) nextZ[ (a) + nzones * (b) ]
   #define next(a,b) next[ (a) + (ncornr+1)  * (b) ]





//   for(int Angle=0;Angle<nAngle;Angle++)

   int Angle = 32*blockIdx.x + threadIdx.x;

   omega0 = soa_omega(0,Angle);
   omega1 = soa_omega(1,Angle);
   omega2 = soa_omega(2,Angle);

   int ndone = 0;

   omega_A_fp += Angle * nzones * size_maxcf * size_maxCorner;
   omega_A_ez += Angle * nzones * size_maxcf * size_maxCorner;

   for(ii=0;ii<nzones;ii++)
   {
 
     int zone = nextZ(ii,Angle) - 1;


     int nCorner   = soa_nCorner[zone];
     int nCFaces   = soa_nCFaces[zone];
     int c0        = soa_c0[zone] ;

     for(i=0;i<nCorner;i++)
     {

       int ic      = next(ndone+i,Angle);
       c       = ic - c0 - 1;

 
       for(icface=0;icface<nCFaces;icface++)
       {
         omega_A_fp(icface,c,zone) =  omega0*soa_A_fp(0,icface,c,zone) + 
                        omega1*soa_A_fp(1,icface,c,zone) + 
                        omega2*soa_A_fp(2,icface,c,zone);
         int icfp    = soa_Connect(0,icface,c,zone) - 1;
         int ib      = soa_Connect(1,icface,c,zone) - 1;
         int cez     = soa_Connect(2,icface,c,zone) - 1;
         soa_Connect_ro(0,icface,c,zone) = icfp;
         soa_Connect_ro(1,icface,c,zone) = ib  ;
         soa_Connect_ro(2,icface,c,zone) = cez ;

         //if (ig==0) printf("Angle,zone,c,icface,afp=%d,%d,%d,%d,%f\n",Angle,zone,c,icface,omega_A_fp(icface,c,zone));
       }


       for(icface=0;icface<nCFaces;icface++)
       {

         omega_A_ez(icface,c,zone) = omega0*soa_A_ez(0,icface,c,zone) + omega1*soa_A_ez(1,icface,c,zone) + omega2*soa_A_ez(2,icface,c,zone) ;
         //if (ig==0) printf("Angle,zone,c,icface,afp=%d,%d,%d,%d,%f\n",Angle,zone,c,icface,omega_A_ez(icface,c,zone));
       }


     } 

     ndone = ndone + nCorner;
   }
  }




}






